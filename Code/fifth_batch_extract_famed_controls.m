%% 05_batch_extract_famed_controls_CSV_FIX.m
% Extract annotated REAL control windows, matching the positive dataset.
% Requires Brainstorm's in_fread and the existing 234-channel map.
% Sources: BCH001-012 control trials (RAID03), BCH017 Control_Zhenous
% raw events (RAID02); ALL extracted signals come from positive-stage RAID02.
% Does not alter either Brainstorm database. Outputs separate MAT/CSV files.
%
% IMPORTANT: Positive X234 files contain data from different preprocessing
% stages across subjects; infer the exact stage per subject from the
% verified positive manifest (and verify BCH017 uses raw_notch_band).
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
if ~isfolder(outputFolder), mkdir(outputFolder); end
manifestPath = fullfile(outputFolder,'control_manifest.csv');
failuresPath = fullfile(outputFolder,'control_failures.csv');

% APPEND MODE: the first five subjects have already produced 63 controls.
% Run BCH017 only; existing MAT/CSV files stay intact. On a fresh empty
% output folder you may instead set subjects to all six subjects below.
subjects = {'BCH017'};
% subjects = {'BCH001','BCH007','BCH009','BCH010','BCH012','BCH017'};

% No arbitrary cap: inspect every annotated window, then decide how many
% controls to use in TRAINING later (e.g., subsample to 236 if desired).
TARGET_FS = 1000;
N_TIME = 1024;
SPIKE_MARGIN_SECONDS = 0.060;
relativeTargetTime = ((0:N_TIME-1)-N_TIME/2)/TARGET_FS;

% Preserve the exact schema of the existing manifest and failure audit.
manifestColumns = {'Subject','Trial','OutputFile','SourceBST', ...
    'ControlAnnotationBST','ControlTimeSeconds','OriginalFs', ...
    'PositivePixels','Channels','CenterRule','KnownSpikeIntervals', ...
    'TrialSource'};
failColumns = {'Subject','Trial','Stage','Reason'};
manifest = table('Size',[0 12], ...
    'VariableTypes',{'string','string','string','string','string', ...
    'double','double','double','double','string','double','string'}, ...
    'VariableNames',manifestColumns);
failures = table('Size',[0 4], ...
    'VariableTypes',{'string','string','string','string'}, ...
    'VariableNames',failColumns);

if isfile(manifestPath)
    % Parse and validate the existing audit without MATLAB's automatic
    % delimiter or column-name detection.
    old = read_existing_audit(manifestPath, manifestColumns);
    old = old(:,manifestColumns);
    stringColumns = {'Subject','Trial','OutputFile','SourceBST', ...
        'ControlAnnotationBST','CenterRule','TrialSource'};
    for k = 1:numel(stringColumns)
        fld = stringColumns{k};
        old.(fld) = string(old.(fld));
    end
    % Keep all trial IDs consistently formatted as three digits.
    old.Trial = compose('%03d',str2double(old.Trial));
    numericColumns = {'ControlTimeSeconds','OriginalFs','PositivePixels', ...
        'Channels','KnownSpikeIntervals'};
    for k = 1:numel(numericColumns)
        fld = numericColumns{k};
        if ~isnumeric(old.(fld))
            old.(fld) = str2double(string(old.(fld)));
        end
    end
    assert(all(isfinite(old.ControlTimeSeconds)), ...
        'Existing control manifest contains invalid times.');
    manifest = [manifest;old];
end
if isfile(failuresPath)
    oldFailures = read_existing_audit(failuresPath, failColumns);
    for k = 1:numel(failColumns)
        fld = failColumns{k};
        oldFailures.(fld) = string(oldFailures.(fld));
    end
    failures = [failures;oldFailures(:,failColumns)];
end

% Fail closed on orphan files: never overwrite, omit, or silently lose one.
existingMAT = dir(fullfile(outputFolder,'*_Control_Trial*_aligned_234.mat'));
existingNames = string({existingMAT.name})';
assert(numel(existingNames)==height(manifest) && ...
    (isempty(existingNames) || ...
    isequal(sort(existingNames(:)),sort(string(manifest.OutputFile(:))))), ...
    ['Existing MAT files and control_manifest.csv disagree. ' ...
     'Back up and reconcile them before running this script.']);
previousCount = height(manifest);
fprintf('Preserved %d existing controls and %d prior failure records.\n', ...
    previousCount,height(failures));

% Back up BOTH original audit CSVs before any new controls are written.
% The already-saved control .mat files are never overwritten by this script.
if isfile(manifestPath) || isfile(failuresPath)
    backupFolder = fullfile(outputFolder, ...
        ['audit_backup_' datestr(now,'yyyymmdd_HHMMSSFFF')]);
    assert(~isfolder(backupFolder),'Audit backup folder already exists.');
    [made,msg] = mkdir(backupFolder);
    assert(made,'Could not create audit backup: %s',msg);
    if isfile(manifestPath)
        [copied,msg] = copyfile(manifestPath, ...
            fullfile(backupFolder,'control_manifest.csv'));
        assert(copied,'Could not back up control manifest: %s',msg);
    end
    if isfile(failuresPath)
        [copied,msg] = copyfile(failuresPath, ...
            fullfile(backupFolder,'control_failures.csv'));
        assert(copied,'Could not back up control failures: %s',msg);
    end
    fprintf('Audit CSV backup: %s\n',backupFolder);
end

assert(isfile(mapFile) && isfile(positiveManifestFile), ...
    'Missing shared channel map or positive pairing_manifest.csv.');
M = load(mapFile,'chosenNames');
mapNames = upper(erase(strtrim(string(M.chosenNames(:))),' '));
assert(numel(mapNames)==234 && numel(unique(mapNames))==234, ...
    'Channel map must contain 234 unique names.');
P = readtable(positiveManifestFile,'TextType','string', ...
    'FileType','text','Delimiter',',', ...
    'VariableNamingRule','preserve');
assert(all(ismember({'Subject','IEDFolder','SourceBST','SpikeTimeSeconds'}, ...
    P.Properties.VariableNames)), 'Positive manifest columns missing.');

% Build reference configuration for each subject and enumerate ORIGINAL
% filenames only: data_Control_trial001.mat, never *_02.mat etc.
configs = cell(numel(subjects),1);
controlFiles = cell(numel(subjects),1);
pointers = ones(numel(subjects),1);
usedWindows = containers.Map('KeyType','char','ValueType','any');
rawEventCache = containers.Map('KeyType','char','ValueType','any');
numberSaved = previousCount;

% Include earlier controls in the overlap check (also makes reruns safe).
for j = 1:height(manifest)
    [~,base] = fileparts(char(manifest.SourceBST(j)));
    recording_identity(base); % Verify the saved source follows our naming scheme.
    key = [char(manifest.Subject(j)) '|' base];
    bounds = double(manifest.ControlTimeSeconds(j)) + ...
        [relativeTargetTime(1),relativeTargetTime(end)];
    if isKey(usedWindows,key)
        usedWindows(key) = [usedWindows(key); bounds];
    else
        usedWindows(key) = bounds;
    end
end

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

        if strcmp(subject,'BCH017')
            % BCH017 has NO Control trial files. Read Control_Zhenous points
            % directly from the continuous raw F.events(16).times.
            annotationBase = '4672078_03_raw_notch_band';
            annotationDir = fullfile(positiveRoot,subject, ...
                ['@raw' annotationBase]);
            annotationMat = fullfile(annotationDir, ...
                ['data_0raw_' annotationBase '.mat']);
            annotationBst = fullfile(annotationDir,[annotationBase '.bst']);
            assert(isfile(annotationMat) && isfile(annotationBst), ...
                'BCH017 Control_Zhenous raw MAT/BST is missing.');
            [annotationRun,annotationStage] = recording_identity(annotationBase);
            assert(strcmpi(annotationStage,char(stages(1))), ...
                'BCH017 annotation stage does not match positive stage.');
            assert(any(strcmpi(runNames,annotationRun)), ...
                'BCH017 annotation run absent from positive manifest.');
            A = load(annotationMat,'F');
            assert(isfield(A,'F') && isfield(A.F,'events') && ...
                numel(A.F.events)>=16, 'BCH017 F.events(16) is missing.');
            ev = A.F.events(16);
            assert(strcmpi(strtrim(string(ev.label)),'Control_Zhenous'), ...
                'BCH017 F.events(16) is not Control_Zhenous.');
            controlTimes = raw_event_centers(ev.times);
            assert(~isempty(controlTimes) && all(isfinite(controlTimes)), ...
                'BCH017 Control_Zhenous has no valid event times.');
            assert(numel(unique(controlTimes))==numel(controlTimes), ...
                'Duplicate BCH017 control centers: review annotations.');
            configs{si} = struct('stage',char(stages(1)), ...
                'referenceRuns',runNames,'C',C,'megIdx',megIdx, ...
                'mapIdx',mapIdx,'positiveRows',ps, ...
                'annotationBst',annotationBst, ...
                'annotationMat',annotationMat, ...
                'annotationBase',annotationBase, ...
                'annotationDir',annotationDir, ...
                'controlTimes',controlTimes);
            controlFiles{si} = 1:numel(controlTimes);
            fprintf('%s: %d Control_Zhenous annotations from F.events(16); stage=%s\n', ...
                subject,numel(controlTimes),char(stages(1)));
            continue;
        end

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
        failures(end+1,:) = {string(subject),string('ALL'),string('SETUP'),string(ME.message)}; %#ok<SAGROW>
        fprintf('SKIP %s setup: %s\n',subject,ME.message);
    end
end

%% Round-robin across subjects if the all-six option is selected.
while true
    remaining = false;
    for si = 1:numel(subjects)
        if isempty(configs{si}) || pointers(si)>numel(controlFiles{si})
            continue;
        end
        remaining = true;
        subject = subjects{si};
        cfg = configs{si};
        trialNumber = pointers(si);
        pointers(si) = pointers(si)+1;
        if strcmp(subject,'BCH017')
            trialID = sprintf('%03d',trialNumber); % raw event number, not a trial file
            controlTrial = cfg.annotationMat;
        else
            fileEntry = controlFiles{si}(trialNumber);
            trialToken = regexp(fileEntry.name, ...
                '^data_Control_trial(\d{3})\.mat$','tokens','once');
            trialID = trialToken{1};
            controlTrial = fullfile(fileEntry.folder,fileEntry.name);
        end
        outName = sprintf('%s_Control_Trial%s_aligned_234.mat',subject,trialID);
        outPath = fullfile(outputFolder,outName);
        if isfile(outPath)
            fprintf('EXISTING %s Trial%s: preserved, not overwritten.\n', ...
                subject,trialID);
            continue;
        end

        try
            %% Determine absolute control center (two annotation formats)
            if strcmp(subject,'BCH017')
                controlSourceBst = cfg.annotationBst;
                controlBstDir = cfg.annotationDir;
                controlBase = cfg.annotationBase;
                controlTime = double(cfg.controlTimes(trialNumber));
                centerRule = 'Control_Zhenous_raw_event';
            else
                S = load(controlTrial,'History','Events','Time');
                assert(isfield(S,'History') && size(S.History,1)>=3 && ...
                    size(S.History,2)>=3 && isfield(S,'Time'), ...
                    'Control History{1,3}, History{3,3}, or Time missing.');
                controlSourceBst = parse_history_bst(S.History{1,3});
                assert(isfile(controlSourceBst), ...
                    'Annotated control source BST missing: %s',controlSourceBst);
                assert(strcmpi(fileparts(fileparts(controlSourceBst)), ...
                    fullfile(controlRoot,subject)), ...
                    'Control BST belongs to another subject.');
                [controlBstDir,controlBase] = fileparts(controlSourceBst);
            end
            assert(isfile(controlSourceBst), ...
                'Control annotation BST is missing: %s',controlSourceBst);
            [runKey,controlStage] = recording_identity(controlBase);
            if strcmp(subject,'BCH017')
                assert(strcmpi(controlStage,'_raw_notch_band'), ...
                    'BCH017 annotation must originate from raw_notch_band.');
            else
                assert(strcmpi(controlStage,'_raw_notch_band_bl'), ...
                    'Existing control trial source is not raw_notch_band_bl.');
            end
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

            if ~strcmp(subject,'BCH017')
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
            end
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

            %% Pre-validate the new audit row BEFORE saving the MAT file.
            newRow = table(string(subject),string(trialID),string(outName), ...
                string(targetBst),string(controlSourceBst),double(controlTime), ...
                double(fs),0,234,string(centerRule),double(numel(E.spikes)), ...
                string(controlTrial),'VariableNames',manifestColumns);
            updatedManifest = [manifest;newRow];

            %% Save validated signal and its manifest (never overwrite).
            assert(~isfile(outPath),'Refusing to overwrite existing output.');
            save(outPath,'X234','Yseg234','yClass','channelNames234', ...
                'relativeTargetTime','controlTime','originalFs', ...
                'sourceBst','controlSourceBst','trialSource','subjectID', ...
                'centerRule','-v7.3');
            manifest = updatedManifest;
            writetable(manifest,manifestPath); % checkpoint each success
            numberSaved = numberSaved+1;
            if ~isKey(usedWindows,cacheKey)
                usedWindows(cacheKey) = [windowStart windowEnd];
            else
                usedWindows(cacheKey) = [usedWindows(cacheKey);windowStart windowEnd];
            end
            fprintf('OK %s Control%s | %s | 234x1024 | %s | total=%d\n', ...
                subject,trialID,targetBase,centerRule,numberSaved);
        catch ME
            failures(end+1,:) = {string(subject),string(trialID),string('TRIAL'),string(ME.message)}; %#ok<SAGROW>
            fprintf('SKIP %s Trial%s: %s\n',subject,trialID,ME.message);
        end
    end
    if ~remaining, break; end
end

%% Save audit tables only after all source files have been processed.
writetable(manifest,manifestPath);
writetable(failures,failuresPath);
fprintf('\nDONE: %d NEW genuine controls; %d TOTAL preserved/new; %d failure records.\n', ...
    numberSaved-previousCount,numberSaved,height(failures));
fprintf('Folder: %s\n',outputFolder);
fprintf('Review the manifest and all skips; controls are NOT filtered or normalized yet.\n');

%% ===== Local functions =====
function T = read_existing_audit(csvPath, expectedHeaders)
    % Validate the actual header rather than trusting MATLAB's automatic
    % renaming of imported variable names. Never remap incompatible CSVs.
    fid = fopen(csvPath,'r');
    assert(fid~=-1,'Cannot read existing audit file: %s',csvPath);
    fileCloser = onCleanup(@() fclose(fid)); %#ok<NASGU>
    headerLine = fgetl(fid);
    assert(ischar(headerLine),'Empty audit CSV: %s',csvPath);
    headerLine = strrep(headerLine,char(65279),''); % optional UTF-8 BOM
    headerLine = strrep(headerLine,char([239 187 191]),'');
    actualHeaders = parse_audit_csv_line(strtrim(headerLine));
    assert(isequal(actualHeaders(:),expectedHeaders(:)), ...
        'Audit CSV header differs from expected schema: %s',csvPath);

    % Avoid readtable auto-detection entirely: on some MATLAB versions it
    % guesses the wrong delimiter and reads the entire header as ONE column.
    % The file header was verified above; parse every data row as actual CSV.
    nColumns = numel(expectedHeaders);
    rawRows = cell(0,nColumns);
    lineNumber = 1;
    while true
        dataLine = fgetl(fid);
        if ~ischar(dataLine)
            break;
        end
        lineNumber = lineNumber+1;
        if isempty(strtrim(dataLine))
            continue; % Ignore a blank line, not an actual audit record.
        end
        cells = parse_audit_csv_line(dataLine);
        assert(numel(cells)==nColumns, ...
            'Malformed CSV at line %d: expected %d columns, found %d: %s', ...
            lineNumber,nColumns,numel(cells),csvPath);
        rawRows(end+1,:) = cells; %#ok<AGROW>
    end
    T = cell2table(rawRows,'VariableNames',expectedHeaders);
    for c = 1:nColumns
        % Keep every field verbatim until the caller explicitly converts
        % numeric columns; this preserves zero-padded trial IDs and paths.
        T.(expectedHeaders{c}) = string(T.(expectedHeaders{c}));
    end
end

function fields = parse_audit_csv_line(line)
    if ~isempty(line) && line(end)==char(13)
        line(end) = []; % CRLF safety for Windows-generated CSVs
    end
    % RFC-style one-line CSV parsing. Handles commas inside double quotes
    % and escaped quotes (""); refuses a malformed, unclosed quoted field.
    fields = cell(1,0);
    token = '';
    quoted = false;
    i = 1;
    while i <= numel(line)
        ch = line(i);
        if ch == '"'
            if quoted && i < numel(line) && line(i+1) == '"'
                token = [token '"']; %#ok<AGROW>
                i = i+1;
            else
                quoted = ~quoted;
            end
        elseif ch == ',' && ~quoted
            fields{end+1} = token; %#ok<AGROW>
            token = '';
        else
            token = [token ch]; %#ok<AGROW>
        end
        i = i+1;
    end
    assert(~quoted,'Malformed CSV: unmatched double quote.');
    fields{end+1} = token;
end

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

function centers = raw_event_centers(t)
    % Brainstorm points: 1xN. Intervals: 2xN (center each interval).
    t = double(t);
    assert(~isempty(t) && ismatrix(t), ...
        'Control_Zhenous times must be a nonempty 1xN or 2xN matrix.');
    if size(t,1)==2
        assert(all(t(2,:)>=t(1,:)), ...
            'Control_Zhenous intervals contain reversed bounds.');
        centers = mean(t,1)';
    else
        assert(isvector(t), ...
            'Unexpected Control_Zhenous time dimensions.');
        centers = t(:);
    end
    assert(all(isfinite(centers)), ...
        'Control_Zhenous times include nonfinite values.');
end
