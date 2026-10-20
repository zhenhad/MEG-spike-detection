%% Select top 10% high-power MEG channels across subjects:
% [BCH001, BCH007, BCH009,BCH010 ,BCH012,BCH017]

clear; clc;
rootFolder = '\\192.168.0.101\papadelis_raid_02\Hmayag\MEEG_Simulations\data';
subjects = {'BCH001','BCH007','BCH009', ...
            'BCH010','BCH012','BCH017'};
targetFolders = {'IEDs_MEG_Christos', ...
                 'IEDs_MEG_COMMON_Giorgos'};
for s = 1:numel(subjects)
    subjectFolder = fullfile(rootFolder, subjects{s});
    if ~isfolder(subjectFolder)
        warning('Subject folder not found: %s', subjectFolder);
        continue;
    end
    for f = 1:numel(targetFolders)
        % Search recursively for the requested folder
        folderMatches = dir(fullfile(subjectFolder, '**', targetFolders{f}));
        folderMatches = folderMatches([folderMatches.isdir]);
        for d = 1:numel(folderMatches)
            folder = fullfile(folderMatches(d).folder, ...
                              folderMatches(d).name);
            fprintf('\nProcessing: %s\n', folder);
            % Find PSD files, regardless of timestamp suffix
            psdFiles = dir(fullfile(folder, ...
                'timefreq_trial*_psd_*.mat'));
            if isempty(psdFiles)
                warning('No PSD files found: %s', folder);
                continue;
            end
            results = {};
            headers = {};
            for i = 1:numel(psdFiles)
                psdName = psdFiles(i).name;
                token = regexp(psdName, ...
                    '^timefreq_trial(\d+)_psd_.*\.mat$', ...
                    'tokens', 'once');
                if isempty(token)
                    continue;
                end
                trialNum = str2double(token{1});
                trialID = sprintf('trial%03d', trialNum);
                psdPath = fullfile(folder, psdName);
                try
                    P = load(psdPath);
                    %% Validate PSD variables
                    if ~isfield(P,'TF') || ...
                       ~isfield(P,'Freqs') || ...
                       ~isfield(P,'RowNames')
                        warning('Missing PSD variables: %s', psdPath);
                        continue;
                    end
                    %% Convert 306 x 1 x 60 into 306 x 60
                    TF = squeeze(P.TF);
                    freqs = P.Freqs(:)';
                    if size(TF,2) ~= numel(freqs) && ...
                       size(TF,1) == numel(freqs)
                        TF = TF';
                    end
                    if size(TF,2) ~= numel(freqs)
                        warning('Unexpected PSD dimensions: %s', psdPath);
                        continue;
                    end
                    %% Select 1-80 Hz
                    freqIdx = freqs >= 1 & freqs <= 80;

                    if ~any(freqIdx)
                        warning('No frequencies within 1-80 Hz: %s', psdPath);
                        continue;
                    end
                    %% Extract MEG channels only
                    rowNames = P.RowNames(:);

                    if size(TF,1) ~= numel(rowNames)
                        warning('Channel count mismatch: %s', psdPath);
                        continue;
                    end
                    isMEG = startsWith(string(rowNames), 'MEG');
                    megNames = rowNames(isMEG);
                    megTF = TF(isMEG, :);
                    if isempty(megNames)
                        warning('No MEG channels: %s', psdPath);
                        continue;
                    end
                    %% Mean PSD power over 1-80 Hz
                    power = mean(megTF(:,freqIdx), 2);
                    %% Select channels above the 90th percentile
                    selected = power > prctile(power,90);
                    names = megNames(selected);
                    %% Store results
                    headers{end+1} = sprintf('Trial_%03d', trialNum);
                    column = cellstr(string(names(:)));
                    results(1:numel(column),end+1) = column;
                    fprintf('%s: selected %d / %d MEG channels\n', ...
                        trialID, numel(names), numel(megNames));
                    %% Find corresponding Brainstorm trial
                    trialFiles = dir(fullfile(folder, ...
                        sprintf('data_*_trial%03d.mat',trialNum)));
                    if numel(trialFiles) == 1
                        trialPath = fullfile(folder,trialFiles(1).name);
                        % Add field without rewriting other variables
                        high_power_channel_names = names;
                        save(trialPath, ...
                            'high_power_channel_names','-append');
                    elseif isempty(trialFiles)
                        warning('Trial data file missing: %s',trialID);
                    else
                        warning('Multiple trial files for %s; skipped update.', ...
                            trialID);
                    end
                catch ME
                    warning('Failed: %s\n%s', psdName, ME.message);
                end
            end
            %% Export CSV
            if isempty(headers)
                warning('No valid PSD files processed: %s',folder);
                continue;
            end
            % Pad columns to equal length
            nRows = size(results,1);
            nCols = numel(headers);
            padded = cell(nRows,nCols);
            padded(:) = {''};
            padded(1:size(results,1),1:size(results,2)) = results;
            output = cell2table(padded, ...
                'VariableNames',headers);
            csvPath = fullfile(folder,'HighPower_90percent.csv');
            writetable(output,csvPath);
            fprintf('CSV saved: %s\n',csvPath);
        end
    end
end
fprintf('\nAll subjects processed.\n');