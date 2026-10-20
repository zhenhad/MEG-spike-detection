%% 05_batch_extract_famed_controls_CHANNEL_FIX.m
% Extract annotated REAL control windows, matching the positive dataset.
% Requires Brainstorm's in_fread and the existing 234-channel map.
% Sources: control annotations (raid_03); ORIGINAL SIGNALS (raid_02).
% Does not alter either Brainstorm database. Outputs separate MAT/CSV files.
%
% IMPORTANT: Positive X234 files contain data from different preprocessing
% stages across subjects (BCH001: raw_notch; other 5: raw_notch_band).
% Match the positive stage PER SUBJECT; apply a common 3-35 Hz filter and
% identical normalization to BOTH classes later, not to controls alone.

clear; clc;
assert(exist('in_fread','file') ~= 0, ...
    'Start Brainstorm first: in_fread must be available.');

positiveRoot = '\\192.168.0.101\papadelis_raid_02\Hmayag\MEEG_Simulations\data';
controlRoot  = '\\192.168.0.101\papadelis_raid_03\Glykeria\brainstorm_db\MEEG_Simulations\data';
projectRoot = fileparts(positiveRoot);
mapFile = fullfile(projectRoot, 'FAMED_channel_map_234.mat');
positiveManifestFile = fullfile(projectRoot, ...
    'FAMED_aligned_six_subjects','pairing_manifest.csv');
outputFolder = fullfile(projectRoot,'FAMED_aligned_controls');
if isfolder(outputFolder)
    existing = dir(fullfile(outputFolder,'*_Control_Trial*_aligned_234.mat'));
    assert(isempty(existing), ...
        ['The output folder already contains control MAT files. Move or ' ...
         'rename it before rerunning to prevent stale files.']);
else
    mkdir(outputFolder);
end

% TEST BCH001 first. Once validated, replace with the five-subject line below.
subjects = {'BCH001','BCH007','BCH009','BCH010','BCH012','BCH017'};
% subjects = {'BCH001','BCH007','BCH009','BCH010','BCH012'};
% BCH017 deliberately excluded: it has no annotated controls.
TARGET_CONTROLS = 236;  % Maximum, not a promise or synthetic oversampling.
TARGET_FS = 1000;
N_TIME = 1024;
SPIKE_MARGIN_SECONDS = 0.060; % Also reject spike margins around full window.
relativeTargetTime = ((0:N_TIME-1)-N_TIME/2)/TARGET_FS;

assert(isfile(mapFile) && isfile(positiveManifestFile), ...
    'Missing shared channel map or positive pairing_manifest.csv.');
M = load(mapFile,'chosenNames');
mapNames = upper(erase(strtrim(string(M.chosenNames(:))),' '));
assert(numel(mapNames)==234 && numel(unique(mapNames))==234, ...
    'Channel map must contain 234 unique names.');
P = readtable(positiveManifestFile,'TextType','string');
assert(all(ismember({'Subject','IEDFolder','SourceBST','SpikeTimeSeconds'}, ...
    P.Properties.VariableNames)), 'Positive manifest columns missing.');

% Build reference configuration for each subject and enumerate ORIGINAL
% filenames only: data_Control_trial001.mat, never *_02.mat etc.
configs = cell(numel(subjects),1);
controlFiles = cell(numel(subjects),1);
pointers = ones(numel(subjects),1);
issues = cell(0,4);    % Subject, trial, stage, reason
records = cell(0,12); % Per-sample output manifest
usedWindows = containers.Map('KeyType','char','ValueType','any');
rawEventCache = containers.Map('KeyType','char','ValueType','any');
numberSaved = 0;

for si = 1:numel(subjects)
    subject = subjects{si};
    try
        ps = P(strcmpi(string(P.Subject),subject),:);
        assert(~isempty(ps),'No positive reference recordings for subject.');
        stageNames = strings(height(ps),1);
        runNames = strings(height(ps),1);
        for j = 1:height(ps)
            [~,bn] = fileparts(char(ps.SourceBST(j)));
            [runNames(j),stageNames(j)] = recording_identity(bn);
        end
        stages = unique(stageNames);
        assert(numel(stages)==1, ...
            'Positive samples use multiple recording stages; inspect individually.');
        iedFolder = char(ps.IEDFolder(1));
        posChannelFiles = dir(fullfile(positiveRoot,subject,iedFolder,'channel*.mat'));
        assert(numel(posChannelFiles)==1, ...
            'Expected exactly one positive-reference channel MAT.');
        C = load(fullfile(posChannelFiles(1).folder,posChannelFiles(1).name),'Channel');
        assert(isfield(C,'Channel'),'Positive channel MAT lacks Channel.');
        allNames = upper(erase(strtrim(string({C.Channel.Name})'),' '));
        megIdx = find(startsWith(allNames,'MEG'));
        megNames = allNames(megIdx);
        [ok,mapIdx] = ismember(mapNames,megNames);
        assert(all(ok) && numel(unique(mapIdx))==234, ...
            'Shared 234-channel map does not match this subject.');

        cf = fullfile(controlRoot,subject,'Control');
        assert(isfolder(cf),'Control annotation folder missing.');
        dirResult = dir(fullfile(cf,'data_Control_trial*.mat'));
        keep = ~cellfun('isempty',regexp({dirResult.name}, ...
            '^data_Control_trial\d{3}\.mat$','once'));
        dirResult = dirResult(keep);
        [~,order] = sort({dirResult.name});
        dirResult = dirResult(order);
        assert(~isempty(dirResult),'No original control trial files found.');

        % The raid_03 Control channel file describes the ANNOTATION source,
        % not the signal we extract. Its order/types can differ from raid_02.
        % Reading its channels by index would be unsafe, so it is not used.
        % All signal channels below are read exclusively from raid_02 with
        % the SAME reference C, megIdx, and 234-row map as the positives.
        ctrlChannelFiles = dir(fullfile(cf,'channel*.mat'));
        if numel(ctrlChannelFiles)==1
            CC = load(fullfile(ctrlChannelFiles(1).folder, ...
                ctrlChannelFiles(1).name),'Channel');
            if isfield(CC,'Channel')
                controlNames = upper(erase(strtrim(string({CC.Channel.Name})'),' '));
                controlTypes = upper(strtrim(string({CC.Channel.Type})'));
                positiveTypes = upper(strtrim(string({C.Channel.Type})'));
                if ~isequal(controlNames,allNames) || ...
                        ~isequal(controlTypes,positiveTypes)
                    fprintf(['INFO %s: raid_03 Control channel metadata ' ...
                        'differs from raid_02. Ignoring annotation-side ' ...
                        'channel order; extraction uses raid_02 only.\n'],subject);
                end
            end
        elseif numel(ctrlChannelFiles)>1
            fprintf(['INFO %s: multiple optional Control channel files; ' ...
                'extraction uses raid_02 channel reference only.\n'],subject);
        end

        configs{si} = struct('stage',char(stages(1)), ...
            'referenceRuns',runNames,'C',C,'megIdx',megIdx, ...
            'mapIdx',mapIdx,'positiveRows',ps);
        controlFiles{si} = dirResult;
        fprintf('%s: %d original controls; positive stage = %s\n', ...
            subject,numel(dirResult),char(stages(1)));
    catch ME
        configs{si} = [];
        controlFiles{si} = [];
        issues(end+1,:) = {subject,'ALL','SETUP',ME.message}; %#ok<SAGROW>
        fprintf('SKIP %s setup: %s\n',subject,ME.message);
    end
end

%% Round-robin across subjects to avoid first-subject-only selection
while numberSaved < TARGET_CONTROLS
    remaining = false;
    for si = 1:numel(subjects)
        if isempty(configs{si}) || pointers(si)>numel(controlFiles{si})
            continue;
        end
        remaining = true;
        subject = subjects{si};
        cfg = configs{si};
        fileEntry = controlFiles{si}(pointers(si));
        pointers(si) = pointers(si)+1;
        trialToken = regexp(fileEntry.name,'^data_Control_trial(\d{3})\.mat$', ...
            'tokens','once');
        trialID = trialToken{1};
        controlTrial = fullfile(fileEntry.folder,fileEntry.name);

        try
            %% Control annotation source and timing
            S = load(controlTrial,'History','Events','Time');
            assert(isfield(S,'History') && size(S.History,1)>=3 && ...
                size(S.History,2)>=3 && isfield(S,'Time'), ...
                'Control History{1,3}, History{3,3}, or Time is missing.');
            controlSourceBst = parse_history_bst(S.History{1,3});
            assert(isfile(controlSourceBst), ...
                'Annotated control source BST is missing: %s',controlSourceBst);
            assert(strcmpi(fileparts(fileparts(controlSourceBst)), ...
                fullfile(controlRoot,subject)), ...
                'Control source BST belongs to a different subject folder.');
            [controlBstDir,controlBase] = fileparts(controlSourceBst);
            [runKey,controlStage] = recording_identity(controlBase);
            assert(strcmpi(controlStage,'_raw_notch_band_bl'), ...
                'Control source is not the expected *_raw_notch_band_bl stage.');
            targetBase = [char(runKey) cfg.stage];
            targetDir = fullfile(positiveRoot,subject,['@raw' targetBase]);
            targetBst = fullfile(targetDir,[targetBase '.bst']);
            targetMat = fullfile(targetDir,['data_0raw_' targetBase '.mat']);
            assert(isfile(targetBst) && isfile(targetMat), ...
                'Same-run positive-stage raw signal is missing: %s',targetBst);

            ctrlMat = fullfile(controlBstDir,['data_0raw_' controlBase '.mat']);
            assert(isfile(ctrlMat),'Control-stage raw metadata missing: %s',ctrlMat);
            CR = load(ctrlMat,'F');
            R = load(targetMat,'F','ChannelFlag');
            assert(isfield(CR,'F') && isfield(R,'F') && ...
                isfield(CR.F,'prop') && isfield(R.F,'prop'), ...
                'Invalid control or positive raw metadata.');
            fs = double(R.F.prop.sfreq);
            ctrlFs = double(CR.F.prop.sfreq);
            assert(isfinite(fs) && fs>0 && abs(fs-ctrlFs)<1e-3, ...
                'Control and extraction-source sampling rates differ.');
            tBounds = double(R.F.prop.times(:)');
            ctrlBounds = double(CR.F.prop.times(:)');
            assert(numel(tBounds)==2 && numel(ctrlBounds)==2 && ...
                all(isfinite([tBounds ctrlBounds])) && ...
                max(abs(tBounds-ctrlBounds)) <= 2/fs+1e-4, ...
                'Control/target recording time coordinates differ.');
            if isfield(R,'ChannelFlag') && ~isempty(R.ChannelFlag)
                assert(numel(R.ChannelFlag)==numel(cfg.C.Channel), ...
                    'Target recording channel count differs from channel file.');
            end
            % For safety, use only a run already represented in the
            % positive manifest. A new run needs a separate validation of
            % its channel layout before indexing it with the positive C.
            assert(any(strcmpi(cfg.referenceRuns,runKey)), ...
                ['Control run is absent from positive manifest. Verify ' ...
                 'run-specific channel layout before extracting it.']);
            sFile = R.F;
            assert(isfield(sFile,'filename'), ...
                'Brainstorm raw metadata lacks its filename.');
            [~,metaBase,metaExt] = fileparts(char(sFile.filename));
            assert(strcmpi([metaBase metaExt],[targetBase '.bst']), ...
                'Raw metadata points to a different binary recording.');
            sFile.filename = targetBst; % Always read raid_02, never filtered raid_03.

            trialTime = double(S.Time(:)');
            histInterval = parse_history_interval(S.History{3,3});
            assert(numel(trialTime)>=2 && all(diff(trialTime)>0) && ...
                abs(diff(histInterval)-diff(trialTime([1 end]))) <= 2/fs+1e-4, ...
                'Control History interval disagrees with trial Time.');
            [relativeCenter,centerRule] = control_annotation_center(S,trialTime);
            assert(relativeCenter>=trialTime(1)-2/fs && ...
                relativeCenter<=trialTime(end)+2/fs, ...
                'Control annotation lies outside imported trial.');
            controlTime = histInterval(1)+(relativeCenter-trialTime(1));
            targetTime = controlTime+relativeTargetTime;
            assert(targetTime(1)>=tBounds(1) && targetTime(end)<=tBounds(2), ...
                'Full 1024-sample control window crosses recording boundary.');

            %% All known spike events: raw Events plus ALL original IED trials
            cacheKey = [subject '|' targetBase];
            if ~isKey(rawEventCache,cacheKey)
                [spikeIntervals,badIntervals] = collect_exclusions( ...
                    sFile,positiveRoot,subject,runKey,cfg.positiveRows);
                rawEventCache(cacheKey) = struct( ...
                    'spikes',spikeIntervals,'bad',badIntervals);
            end
            E = rawEventCache(cacheKey);
            assert(~isempty(E.spikes), ...
                'No known spike annotations available for this recording; cannot verify control.');
            windowStart = targetTime(1);
            windowEnd = targetTime(end);
            assert(~interval_overlap(E.spikes,windowStart,windowEnd, ...
                SPIKE_MARGIN_SECONDS), ...
                'Window overlaps a known IED/spike (+/- 60 ms guard).');
            assert(~interval_overlap(E.bad,windowStart,windowEnd,0), ...
                'Window overlaps an annotated BAD interval.');

            % Explicitly exclude ANY overlap with the already-saved positive
            % 1.024-s windows from this subject/run (independent of event list).
            positiveTimes = positive_times_for_run(cfg.positiveRows,runKey);
            if ~isempty(positiveTimes)
                assert(~any((positiveTimes-0.512 <= windowEnd) & ...
                    (positiveTimes+0.511 >= windowStart)), ...
                    'Window overlaps an existing positive training window.');
            end

            % Prevent two selected negatives from sharing signal samples.
            if isKey(usedWindows,cacheKey)
                previous = usedWindows(cacheKey);
                assert(~any(previous(:,1)<=windowEnd & previous(:,2)>=windowStart), ...
                    'Window overlaps an already selected negative window.');
            end

            %% Read SAME stage as the positive examples and align to 1 kHz
            firstSample = floor((targetTime(1)-0.01)*fs);
            lastSample = ceil((targetTime(end)+0.01)*fs);
            sampleBounds = round(tBounds*fs);
            assert(firstSample>=sampleBounds(1) && lastSample<=sampleBounds(2), ...
                'Raw read bounds fall outside recording.');
            [Fraw,Traw] = in_fread(sFile,cfg.C,1, ...
                [firstSample lastSample],cfg.megIdx);
            Traw = double(Traw(:));
            assert(size(Fraw,1)==numel(cfg.megIdx) && ...
                size(Fraw,2)==numel(Traw) && numel(Traw)>=2 && ...
                all(diff(Traw)>0) && Traw(1)<=targetTime(1) && ...
                Traw(end)>=targetTime(end), ...
                'Raw read does not cover 1024-sample time grid.');
            X = interp1(Traw,double(Fraw.'),targetTime(:),'linear').';
            assert(all(isfinite(X(:))) && ~all(X(:)==0), ...
                'Raw resampling produced nonfinite/all-zero signal.');
            X234 = single(X(cfg.mapIdx,:));
            Yseg234 = false(234,N_TIME);
            yClass = uint8(0);
            channelNames234 = mapNames;
            sourceBst = targetBst;
            originalFs = fs;
            subjectID = subject;
            trialSource = controlTrial;
            assert(isequal(size(X234),[234,N_TIME]) && ...
                isequal(size(Yseg234),[234,N_TIME]), ...
                'Final control dimensions incorrect.');

            %% Save only after validation, never overwrite positive files
            outName = sprintf('%s_Control_Trial%s_aligned_234.mat',subject,trialID);
            outPath = fullfile(outputFolder,outName);
            save(outPath,'X234','Yseg234','yClass','channelNames234', ...
                'relativeTargetTime','controlTime','originalFs', ...
                'sourceBst','controlSourceBst','trialSource','subjectID', ...
                'centerRule','-v7.3');
            numberSaved = numberSaved+1;
            if ~isKey(usedWindows,cacheKey)
                usedWindows(cacheKey) = [windowStart windowEnd];
            else
                usedWindows(cacheKey) = [usedWindows(cacheKey);windowStart windowEnd];
            end
            records(end+1,:) = {subject,trialID,outName,targetBst, ...
                controlSourceBst,controlTime,fs,0,234,centerRule, ...
                numel(E.spikes),controlTrial}; %#ok<SAGROW>
            fprintf('OK %s Trial%s | %s | 234x1024 | %s | %d/%d\n', ...
                subject,trialID,targetBase,centerRule,numberSaved,TARGET_CONTROLS);
        catch ME
            issues(end+1,:) = {subject,trialID,'TRIAL',ME.message}; %#ok<SAGROW>
            fprintf('SKIP %s Trial%s: %s\n',subject,trialID,ME.message);
        end
        if numberSaved>=TARGET_CONTROLS, break; end
    end
    if ~remaining, break; end
end

%% Audits: never claim that target count was reached if it wasn't.
manifest = cell2table(records,'VariableNames', ...
    {'Subject','Trial','OutputFile','SourceBST','ControlAnnotationBST', ...
     'ControlTimeSeconds','OriginalFs','PositivePixels','Channels', ...
     'CenterRule','KnownSpikeIntervals','TrialSource'});
failures = cell2table(issues,'VariableNames', ...
    {'Subject','Trial','Stage','Reason'});
writetable(manifest,fullfile(outputFolder,'control_manifest.csv'));
writetable(failures,fullfile(outputFolder,'control_failures.csv'));
fprintf('\nDONE: %d genuine control windows saved; %d skipped/setup issues.\n', ...
    numberSaved,height(failures));
fprintf('Requested maximum: %d; no missing controls were fabricated.\n', ...
    TARGET_CONTROLS);
fprintf('Folder: %s\n',outputFolder);
fprintf('Review both CSV files and confirm subject coverage before training.\n');

%% ===== Local functions =====
function bstPath = parse_history_bst(historyText)
    txt = char(string(historyText));
    token = regexp(txt,'Import from:\s*(.*?)\.bst\s*\(Event\)', ...
        'tokens','once');
    assert(~isempty(token),'Cannot parse original .bst from History{1,3}.');
    bstPath = [strtrim(token{1}) '.bst'];
end

function interval = parse_history_interval(historyText)
    txt = char(string(historyText));
    nums = regexp(txt,'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?','match');
    assert(numel(nums)==2,'History{3,3} must contain exactly two times.');
    interval = [str2double(nums{1}),str2double(nums{2})];
    assert(all(isfinite(interval)) && interval(2)>interval(1), ...
        'Invalid History interval.');
end

function [runKey,stage] = recording_identity(baseName)
    % Examples: 3950747_03_raw_notch, 3950747_03_raw_notch_band,
    %           3950747_03_raw_notch_band_bl.
    token = regexp(char(baseName), ...
        '^(.+?)(_raw_notch(?:_band)?(?:_bl)?)$', 'tokens','once');
    assert(~isempty(token), 'Unrecognized recording name: %s',char(baseName));
    runKey = string(token{1});
    stage = string(token{2});
end

function [relativeCenter,rule] = control_annotation_center(S,trialTime)
    % Control events can be points (1xN) or intervals (2xN).
    relativeCenter = (trialTime(1)+trialTime(end))/2;
    rule = 'History_midpoint';
    if ~isfield(S,'Events') || ~isstruct(S.Events) || isempty(S.Events)
        return;
    end
    labels = string({S.Events.label});
    ix = find(strcmpi(strtrim(labels),'Control'));
    centers = [];
    for k = ix
        tm = double(S.Events(k).times);
        if isempty(tm), continue; end
        if size(tm,1)==2
            centers = [centers;mean(tm,1)']; %#ok<AGROW>
        else
            centers = [centers;tm(:)]; %#ok<AGROW>
        end
    end
    centers = centers(isfinite(centers) & ...
        centers>=trialTime(1) & centers<=trialTime(end));
    if isempty(centers), return; end
    assert(numel(centers)==1, ...
        'Multiple Control annotation centers in one trial; resolve manually.');
    relativeCenter = centers(1);
    rule = 'Control_event';
end

function [spikeIntervals,badIntervals] = collect_exclusions( ...
        sFile,positiveRoot,subject,runKey,positiveRows)
    spikeIntervals = zeros(0,2);
    badIntervals = zeros(0,2);
    if isfield(sFile,'events') && isstruct(sFile.events)
        [sp,bad] = event_intervals(sFile.events,0,0);
        spikeIntervals = [spikeIntervals;sp];
        badIntervals = [badIntervals;bad];
    end

    % All ORIGINAL IED trial files, including trials that failed mask creation.
    dirs = {'IEDs_MEG_Christos','IEDs_MEG_COMMON_Giorgos'};
    for di = 1:numel(dirs)
        d = fullfile(positiveRoot,subject,dirs{di});
        if ~isfolder(d), continue; end
        trials = dir(fullfile(d,'data_*_trial*.mat'));
        for j = 1:numel(trials)
            if isempty(regexp(trials(j).name, ...
                    '^data_.*_trial\d{3}\.mat$','once'))
                continue;
            end
            try
                T = load(fullfile(trials(j).folder,trials(j).name), ...
                    'History','Time','Events');
                if ~isfield(T,'History') || ~isfield(T,'Time') || ...
                        size(T.History,1)<3 || size(T.History,2)<3
                    continue;
                end
                [~,srcBase] = fileparts(parse_history_bst(T.History{1,3}));
                [thisRun,~] = recording_identity(srcBase);
                if ~strcmpi(thisRun,runKey), continue; end
                histRange = parse_history_interval(T.History{3,3});
                trialStart = double(T.Time(1));
                if isfield(T,'Events') && isstruct(T.Events)
                    [sp,~] = event_intervals(T.Events,histRange(1),trialStart);
                else
                    sp = zeros(0,2);
                end
                if isempty(sp)
                    % Conservative: mark unknown IED trial center as a spike.
                    sp = repmat(mean(histRange),1,2);
                end
                spikeIntervals = [spikeIntervals;sp]; %#ok<AGROW>
            catch ME
                warning('Cannot inspect original IED trial %s: %s', ...
                    trials(j).name,ME.message);
            end
        end
    end

    % Also honor every already-extracted positive event for this recording.
    positiveTimes = positive_times_for_run(positiveRows,runKey);
    spikeIntervals = [spikeIntervals;positiveTimes(:),positiveTimes(:)];
    spikeIntervals = spikeIntervals(all(isfinite(spikeIntervals),2),:);
    badIntervals = badIntervals(all(isfinite(badIntervals),2),:);
end

function times = positive_times_for_run(rows,runKey)
    times = [];
    for k = 1:height(rows)
        [~,base] = fileparts(char(rows.SourceBST(k)));
        [sourceRun,~] = recording_identity(base);
        if strcmpi(sourceRun,runKey)
            times(end+1,1) = double(rows.SpikeTimeSeconds(k)); %#ok<AGROW>
        end
    end
end

function [spikes,bad] = event_intervals(events,absoluteStart,relativeStart)
    % Transform Brainstorm relative trial time to absolute raw time.
    % For raw events, call with 0,0 because their times are already absolute.
    spikes = zeros(0,2);
    bad = zeros(0,2);
    for k = 1:numel(events)
        if ~isfield(events(k),'label') || ~isfield(events(k),'times')
            continue;
        end
        label = char(string(events(k).label));
        isSpike = ~isempty(regexpi(label,'IED|SPIKE','once'));
        isBad = ~isempty(regexpi(label,'^BAD','once'));
        if ~isSpike && ~isBad, continue; end
        t = double(events(k).times);
        if isempty(t), continue; end
        if size(t,1)==2
            bounds = t.';
        else
            times = t(:);
            bounds = [times,times];
        end
        bounds = bounds+absoluteStart-relativeStart;
        bounds = sort(bounds,2);
        bounds = bounds(all(isfinite(bounds),2),:);
        if isSpike, spikes = [spikes;bounds]; end %#ok<AGROW>
        if isBad, bad = [bad;bounds]; end %#ok<AGROW>
    end
end

function yes = interval_overlap(intervals,startTime,endTime,margin)
    if isempty(intervals)
        yes = false;
    else
        yes = any(intervals(:,1)<=endTime+margin & ...
                  intervals(:,2)>=startTime-margin);
    end
end
