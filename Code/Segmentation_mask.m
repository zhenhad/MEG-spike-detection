%% Batch high-power segmentation masks: six BCH subjects
% CSV is preferred. Missing CSV trial columns are recovered from the
% corresponding trial MAT field or directly from that trial's PSD file.
% Saves one .mat and one interactive .fig per annotated trial.
clear; clc;

rootFolder = '\\192.168.0.101\papadelis_raid_02\Hmayag\MEEG_Simulations\data';
subjects = {'BCH001','BCH007','BCH009','BCH010','BCH012','BCH017'};
folderNames = {'IEDs_MEG_Christos','IEDs_MEG_COMMON_Giorgos'};
timeWindow = [-0.060 0.060];  % seconds relative to the annotation

for s = 1:numel(subjects)
    subjectFolder = fullfile(rootFolder,subjects{s});
    if ~isfolder(subjectFolder)
        warning('Missing subject: %s',subjectFolder); continue;
    end

    for q = 1:numel(folderNames)
        paths = {};
        direct = fullfile(subjectFolder,folderNames{q});
        if isfolder(direct), paths{end+1} = direct; end %#ok<SAGROW>
        matches = dir(fullfile(subjectFolder,'**',folderNames{q}));
        for j = 1:numel(matches)
            if matches(j).isdir
                paths{end+1} = fullfile(matches(j).folder,matches(j).name); %#ok<SAGROW>
            end
        end
        paths = unique(paths,'stable');

        for p = 1:numel(paths)
            folder = paths{p};
            csvPath = fullfile(folder,'HighPower_90percent.csv');
            outFolder = fullfile(folder,'HighPowerMasks');
            if ~isfolder(outFolder), mkdir(outFolder); end

            % Read existing CSV but do not skip a trial just because its
            % column was omitted or MATLAB modified its header.
            csvTrials = [];
            csvNames = {};
            if isfile(csvPath)
                try
                    tab = readtable(csvPath,'TextType','string', ...
                        'VariableNamingRule','preserve');
                    columns = string(tab.Properties.VariableNames);
                    for c = 1:numel(columns)
                        tok = regexp(char(columns(c)), ...
                            '(?i)^trial[_\s]*(\d+)$','tokens','once');
                        if isempty(tok), continue; end
                        csvTrials(end+1) = str2double(tok{1}); %#ok<SAGROW>
                        vals = strtrim(string(tab{:,c}));
                        vals = vals(~ismissing(vals) & vals~="" & ...
                            vals~="<missing>" & vals~="NaN");
                        csvNames{end+1} = cellstr(vals(:)); %#ok<SAGROW>
                    end
                catch ME
                    warning('CSV could not be read (%s): %s',csvPath,ME.message);
                end
            else
                warning('CSV missing; recovering from MAT/PSD: %s',csvPath);
            end

            % Locate the channel file.
            channelPath = fullfile(folder,'channel_vectorview306_acc1.mat');
            if ~isfile(channelPath)
                channelPath = fullfile(subjectFolder,'channel_vectorview306_acc1.mat');
            end
            if ~isfile(channelPath)
                candidates = dir(fullfile(subjectFolder,'**','channel_vectorview306_acc1.mat'));
                if isempty(candidates)
                    warning('No channel file for %s',folder); continue;
                end
                channelPath = fullfile(candidates(1).folder,candidates(1).name);
            end
            C = load(channelPath,'Channel');
            allNames = string({C.Channel.Name});
            isMEG = startsWith(strtrim(allNames),'MEG');
            megNames = allNames(isMEG);

            % Original data only: excludes *_HighPowerMask.mat.
            allFiles = dir(fullfile(folder,'data_*_trial*.mat'));
            trialNums = [];
            trialFiles = {};
            for j = 1:numel(allFiles)
                tok = regexp(allFiles(j).name, ...
                    '^data_.*_trial(\d+)\.mat$','tokens','once');
                if isempty(tok), continue; end
                trialNums(end+1) = str2double(tok{1}); %#ok<SAGROW>
                trialFiles{end+1} = fullfile(allFiles(j).folder,allFiles(j).name); %#ok<SAGROW>
            end
            [trialNums,ord] = sort(trialNums);
            trialFiles = trialFiles(ord);
            fprintf('\n%s: %d original trial files\n',folder,numel(trialNums));

            saved = 0;
            recovered = 0;
            for j = 1:numel(trialNums)
                trialNum = trialNums(j);
                trialPath = trialFiles{j};
                fig = [];
                try
                    S = load(trialPath);
                    if ~all(isfield(S,{'F','Time','Events'}))
                        warning('Missing F/Time/Events: %s',trialPath); continue;
                    end

                    % Resolve high-power names in this order: CSV, MAT, PSD.
                    col = find(csvTrials==trialNum,1);
                    highPower = strings(0,1);
                    source = '';
                    if ~isempty(col)
                        highPower = cleanNames(csvNames{col});
                        if ~isempty(highPower), source = 'CSV'; end
                    end
                    if isempty(highPower) && isfield(S,'high_power_channel_names')
                        highPower = cleanNames(S.high_power_channel_names);
                        if ~isempty(highPower), source = 'trial MAT'; end
                    end
                    if isempty(highPower)
                        highPower = recoverFromPSD(folder,trialNum);
                        if ~isempty(highPower), source = 'PSD'; end
                    end
                    if isempty(highPower)
                        warning('Trial %03d: no channel names in CSV/MAT/PSD; skipped.',trialNum);
                        continue;
                    end
                    if isempty(col)
                        csvTrials(end+1) = trialNum; %#ok<SAGROW>
                        csvNames{end+1} = cellstr(highPower); %#ok<SAGROW>
                        recovered = recovered+1;
                    elseif isempty(csvNames{col})
                        csvNames{col} = cellstr(highPower);
                        recovered = recovered+1;
                    end

                    time = double(S.Time(:)');
                    if size(S.F,2)~=numel(time)
                        warning('Time/data length mismatch: %s',trialPath); continue;
                    end
                    if size(S.F,1)==numel(allNames)
                        F = double(S.F(isMEG,:));
                    elseif size(S.F,1)==numel(megNames)
                        F = double(S.F);
                    else
                        warning('Data/channel count mismatch: %s',trialPath); continue;
                    end

                    eventTime = [];
                    eventLabel = '';
                    for e = 1:numel(S.Events)
                        label = char(string(S.Events(e).label));
                        if contains(upper(label),'IED') && contains(upper(label),'MEG') ...
                                && isfield(S.Events(e),'times') && ~isempty(S.Events(e).times)
                            eventTime = double(S.Events(e).times(1));
                            eventLabel = label;
                            break;
                        end
                    end
                    if isempty(eventTime)
                        warning('Trial %03d: no annotated MEG IED event; skipped.',trialNum);
                        continue;
                    end
                    timeMask = time>=eventTime+timeWindow(1) & ...
                               time<=eventTime+timeWindow(2);
                    cleanMEG = upper(erase(strtrim(megNames),' '));
                    cleanHP = upper(erase(strtrim(highPower),' '));
                    hpIdx = find(ismember(cleanMEG,cleanHP));
                    if isempty(hpIdx) || ~any(timeMask)
                        warning('Trial %03d: channel/time mask empty; skipped.',trialNum);
                        continue;
                    end
                    mask = false(size(F));
                    mask(hpIdx,timeMask) = true;
                    SegMask = struct('mask',mask,'time',time,'eventTime',eventTime, ...
                        'channelNames',megNames,'highPowerChannels',highPower, ...
                        'timeWindow',timeWindow,'eventLabel',eventLabel, ...
                        'subject',subjects{s},'sourceCSV',csvPath, ...
                        'highPowerSource',source);

                    [~,baseName] = fileparts(trialPath);
                    outBase = fullfile(outFolder,[baseName '_HighPowerMask']);
                    save([outBase '.mat'],'SegMask','-v7.3');

                    % Stacked traces: black, green inside selected mask, red event.
                    fig = figure('Color','w','Position',[100 50 900 1200], ...
                        'Name',baseName,'Visible','off');
                    ax = axes('Parent',fig,'Position',[0.12 0.08 0.77 0.88]);
                    hold(ax,'on');
                    nChannels = size(F,1);
                    yBase = (1:nChannels)*4;
                    normF = F-mean(F,2);
                    sd = std(normF,0,2);
                    sd(~isfinite(sd) | sd==0)=1;
                    normF = normF./sd;
                    normF(~isfinite(normF))=0;
                    hBlack = gobjects(nChannels,1);
                    hGreen = gobjects(numel(hpIdx),1);
                    for ch = 1:nChannels
                        yy = normF(ch,:)+yBase(ch);
                        hBlack(ch) = plot(ax,time*1000,yy,'k','LineWidth',0.5);
                        k = find(hpIdx==ch,1);
                        if ~isempty(k)
                            yg = yy; yg(~timeMask)=NaN;
                            hGreen(k) = plot(ax,time*1000,yg, ...
                                'Color',[0 0.75 0],'LineWidth',2);
                        end
                    end
                    xline(ax,eventTime*1000,'--r','LineWidth',2, ...
                        'Label',strrep(eventLabel,'_','\_'));
                    ax.YTick = yBase;
                    ax.YTickLabel = cellstr(megNames);
                    ax.FontSize = 5;
                    xlabel(ax,'Time (ms)'); ylabel(ax,'MEG channels');
                    title(ax,strrep(baseName,'_','\_'),'Interpreter','tex');
                    xlim(ax,[min(time) max(time)]*1000);
                    ylim(ax,[0 max(yBase)+4]); box(ax,'off');
                    uicontrol('Parent',fig,'Style','text','Units','normalized', ...
                        'Position',[0.92 0.90 0.06 0.03],'String','Gain', ...
                        'BackgroundColor','w');
                    gainText = uicontrol('Parent',fig,'Style','text', ...
                        'Units','normalized','Position',[0.92 0.87 0.06 0.03], ...
                        'String','1.0x','BackgroundColor','w');
                    slider = uicontrol('Parent',fig,'Style','slider', ...
                        'Units','normalized','Position',[0.94 0.20 0.025 0.65], ...
                        'Min',0.2,'Max',10,'Value',1);
                    slider.Callback = @(src,evt) changeGain(src,gainText, ...
                        hBlack,hGreen,normF,time,yBase,hpIdx,timeMask);
                    savefig(fig,[outBase '.fig']);
                    close(fig); fig=[];
                    saved=saved+1;
                    fprintf('Trial %03d: %d channels (%s); MAT + FIG saved\n', ...
                        trialNum,numel(hpIdx),source);
                catch ME
                    if ~isempty(fig) && isgraphics(fig), close(fig); end
                    warning('Trial %03d failed: %s',trialNum,ME.message);
                end
            end

            % Repair CSV headers/columns for recovered trials, preserving
            % any originally readable trials as well.
            if recovered>0
                [uniqueTrials,keep] = unique(csvTrials,'stable');
                csvNames = csvNames(keep);
                [uniqueTrials,order] = sort(uniqueTrials);
                csvNames = csvNames(order);
                maxRows = max(cellfun(@numel,csvNames));
                cells = repmat({''},maxRows,numel(uniqueTrials));
                headers = cell(1,numel(uniqueTrials));
                for k = 1:numel(uniqueTrials)
                    headers{k} = sprintf('Trial_%03d',uniqueTrials(k));
                    vals = csvNames{k};
                    cells(1:numel(vals),k) = vals(:);
                end
                writetable(cell2table(cells,'VariableNames',headers),csvPath);
                fprintf('Repaired CSV: %s (%d recovered trials)\n',csvPath,recovered);
            end
            fprintf('Completed %s: %d masks saved\n',folder,saved);
        end
    end
end
fprintf('\nFinished all subjects.\n');

function names = cleanNames(values)
    names = strtrim(string(values(:)));
    names = names(~ismissing(names) & names~="" & names~="<missing>" & names~="NaN");
end

function names = recoverFromPSD(folder,trialNum)
    names = strings(0,1);
    psds = dir(fullfile(folder,sprintf('timefreq_trial%03d_psd_*.mat',trialNum)));
    if isempty(psds), return; end
    [~,idx] = max([psds.datenum]); % newest when several timestamps exist
    P = load(fullfile(psds(idx).folder,psds(idx).name));
    if ~all(isfield(P,{'TF','Freqs','RowNames'})), return; end
    TF = squeeze(P.TF);
    freqs = P.Freqs(:)';
    if size(TF,2)~=numel(freqs) && size(TF,1)==numel(freqs)
        TF = TF';
    end
    rowNames = string(P.RowNames(:));
    if size(TF,2)~=numel(freqs) || size(TF,1)~=numel(rowNames)
        return;
    end
    freqIdx = freqs>=1 & freqs<=80;
    megIdx = startsWith(strtrim(rowNames),'MEG');
    if ~any(freqIdx) || ~any(megIdx), return; end
    power = mean(TF(megIdx,freqIdx),2);
    candidates = rowNames(megIdx);
    names = cleanNames(candidates(power>prctile(power,90)));
end

function changeGain(src,gainText,hBlack,hGreen,normF,time,yBase,hpIdx,timeMask)
    gain = src.Value;
    set(gainText,'String',sprintf('%.1fx',gain));
    for ch = 1:size(normF,1)
        set(hBlack(ch),'YData',gain*normF(ch,:)+yBase(ch));
    end
    for k = 1:numel(hpIdx)
        ch = hpIdx(k);
        yy = gain*normF(ch,:)+yBase(ch);
        yy(~timeMask)=NaN;
        set(hGreen(k),'XData',time*1000,'YData',yy);
    end
    drawnow;
end
