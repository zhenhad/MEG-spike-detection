%% Batch extract aligned MEG X/Yseg pairs for six subjects
% Prerequisite: Brainstorm is on the MATLAB path (in_fread available).
% Uses the verified BCH001 Trial001 procedure, selecting only COMMON/Christos.
% Rebuilds labels using selected event if original mask used another event.
% Output: one .mat per trial plus pairing_manifest.csv and failures.csv.
% Does NOT alter the original Brainstorm database or make control samples.

assert(exist('in_fread','file') ~= 0, ...
    'Brainstorm in_fread is not on the MATLAB path. Start Brainstorm first.');

root = '\\192.168.0.101\papadelis_raid_02\Hmayag\MEEG_Simulations\data';
subjects = {'BCH001','BCH007','BCH009','BCH010','BCH012','BCH017'};
iedFolders = {'IEDs_MEG_Christos','IEDs_MEG_COMMON_Giorgos'};
mapFile = fullfile(fileparts(root), 'FAMED_channel_map_234.mat');
outFolder = fullfile(pwd, 'FAMED_aligned_six_subjects');
if ~isfolder(outFolder), mkdir(outFolder); end

map = load(mapFile, 'chosenNames');
mapNames = erase(string(map.chosenNames(:)), ' ');
assert(numel(mapNames)==234 && numel(unique(mapNames))==234, ...
    'The channel map must contain 234 unique channel names.');

TARGET_FS = 1000;
N_TIME = 1024;
relativeTargetTime = ((0:N_TIME-1) - N_TIME/2) / TARGET_FS;

% Keep a complete audit, including failures. Files with errors are skipped.
records = cell(0,9);
failures = cell(0,4);
numberSaved = 0;

for si = 1:numel(subjects)
    subject = subjects{si};
    for fi = 1:numel(iedFolders)
        folderName = iedFolders{fi};
        folder = fullfile(root, subject, folderName);
        if ~isfolder(folder), continue; end

        maskFolder = fullfile(folder,'HighPowerMasks');
        maskFiles = dir(fullfile(maskFolder,'data_*_trial*_HighPowerMask.mat'));
        if isempty(maskFiles)
            fprintf('No masks: %s / %s\n',subject,folderName);
            continue;
        end

        channelFiles = dir(fullfile(folder,'channel*.mat'));
        if numel(channelFiles) ~= 1
            warning('%s / %s: expected one channel file, found %d; skipping folder.', ...
                subject,folderName,numel(channelFiles));
            failures(end+1,:) = {subject,folderName,'ALL', ...
                sprintf('Expected one channel file, found %d',numel(channelFiles))};
            continue;
        end
        C = load(fullfile(channelFiles(1).folder,channelFiles(1).name),'Channel');
        allNames = string({C.Channel.Name})';
        megIdx = find(startsWith(erase(allNames,' '),'MEG'));
        megNames = erase(allNames(megIdx),' ');
        [mapFound,mapIdx] = ismember(mapNames,megNames);
        if ~all(mapFound) || numel(unique(mapIdx)) ~= 234
            warning('%s / %s: 234-channel map mismatch; skipping folder.',subject,folderName);
            failures(end+1,:) = {subject,folderName,'ALL','234-channel map mismatch'};
            continue;
        end

        fprintf('\n=== %s / %s: %d masks ===\n',subject,folderName,numel(maskFiles));
        for mi = 1:numel(maskFiles)
            maskName = maskFiles(mi).name;
            token = regexp(maskName,'_trial(\d+)_HighPowerMask\.mat$','tokens','once');
            if isempty(token), continue; end
            trialID = sprintf('%03d',str2double(token{1}));
            trialName = regexprep(maskName,'_HighPowerMask\.mat$','.mat');
            trialPath = fullfile(folder,trialName);
            maskPath = fullfile(maskFolder,maskName);

            try
                assert(isfile(trialPath),'Corresponding trial MAT is missing: %s',trialPath);
                S = load(trialPath);
                M = load(maskPath,'SegMask');
                assert(isfield(S,'History') && size(S.History,1)>=3 && ...
                    size(S.History,2)>=3,'Trial History{1,3}/History{3,3} missing.');
                assert(isfield(S,'Events') && isfield(S,'Time'), ...
                    'Trial Events or Time missing.');
                assert(isfield(M,'SegMask'),'SegMask variable missing.');
                assert(size(S.F,1)==numel(C.Channel), ...
                    'Trial channels do not match channel file.');

                % Exact source .bst, not a guessed alternative preprocessing stage.
                sourceText = char(string(S.History{1,3}));
                sourceToken = regexp(sourceText, ...
                    'Import from:\s*(.*?)\.bst\s*\(Event\)', 'tokens','once');
                assert(~isempty(sourceToken), ...
                    'Cannot extract the .bst source from History{1,3}.');
                bstPath = [strtrim(sourceToken{1}) '.bst'];
                assert(isfile(bstPath),'Original BST not found: %s',bstPath);
                [bstDir,bstBase] = fileparts(bstPath);
                rawMat = fullfile(bstDir,['data_0raw_' bstBase '.mat']);
                assert(isfile(rawMat),'Original Brainstorm raw MAT not found: %s',rawMat);

                R = load(rawMat,'F');
                assert(isfield(R,'F') && isfield(R.F,'prop') && ...
                    isfield(R.F,'filename'),'Invalid Brainstorm raw metadata.');
                sFile = R.F;
                % Verify raw metadata points to the same actual binary file.
                if ~isfile(sFile.filename)
                    [~,binaryBase,binaryExt] = fileparts(sFile.filename);
                    assert(strcmpi([binaryBase binaryExt],[bstBase '.bst']), ...
                        'Raw metadata references a different binary file.');
                    sFile.filename = bstPath;
                else
                    [~,binaryBase,binaryExt] = fileparts(sFile.filename);
                    assert(strcmpi([binaryBase binaryExt],[bstBase '.bst']), ...
                        'Raw metadata references a different binary file.');
                end
                fs = double(sFile.prop.sfreq);
                assert(isfinite(fs) && fs>0,'Invalid original sampling rate.');

                % Validate the import interval against trial relative time.
                histRange = char(string(S.History{3,3}));
                nums = regexp(histRange, ...
                    '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?','match');
                assert(numel(nums)==2,'History{3,3} must contain two time endpoints.');
                importStart = str2double(nums{1});
                importEnd = str2double(nums{2});
                trialTime = double(S.Time(:)');
                assert(isfinite(importStart) && isfinite(importEnd) && ...
                    numel(trialTime)>1 && importEnd>importStart, ...
                    'Invalid import/trial time range.');
                assert(abs((importEnd-importStart) - ...
                    (trialTime(end)-trialTime(1))) <= (2/fs + 1e-4), ...
                    'History import duration disagrees with trial Time.');

                % Exactly two eligible labels. The old mask generator could
                % select a DIFFERENT MEG event (e.g. Naoro) and record its
                % eventTime. Do not require that old time to match Christos.
                % History import interval identifies the original trial and
                % its center, not the event label used by the mask generator.
                seg = M.SegMask;
                assert(isfield(seg,'eventTime') && isnumeric(seg.eventTime) && ...
                    isscalar(seg.eventTime) && isfinite(seg.eventTime), ...
                    'SegMask.eventTime is missing or invalid.');
                maskEventTime = double(seg.eventTime);
                labels = string({S.Events.label});
                normalizedLabels = upper(strtrim(labels));
                allowedLabels = ["IEDS_MEG_COMMON", "IEDS_MEG_CHRISTOS"];

                % Use trial midpoint as the History import-event anchor.
                % This is the selection criterion if the mask was created
                % around a different annotation.
                trialMid = (trialTime(1) + trialTime(end))/2;
                candTimes = [];
                candLabels = strings(0,1);
                for ei = find(ismember(normalizedLabels,allowedLabels))
                    theseTimes = double(S.Events(ei).times(:));
                    theseTimes = theseTimes(isfinite(theseTimes));
                    for ti = 1:numel(theseTimes)
                        if theseTimes(ti) >= trialTime(1)-1/fs && ...
                                theseTimes(ti) <= trialTime(end)+1/fs
                            candTimes(end+1,1) = theseTimes(ti); %#ok<AGROW>
                            candLabels(end+1,1) = labels(ei); %#ok<AGROW>
                        end
                    end
                end
                assert(~isempty(candTimes), ...
                    'Neither IEDs_MEG_COMMON nor IEDs_MEG_Christos is present within this trial.');

                % Folder-specific preferred label; only these TWO event
                % types are ever considered. Choose timestamp nearest the
                % midpoint of the History import interval.
                if strcmpi(folderName,'IEDs_MEG_Christos')
                    preferredLabel = "IEDS_MEG_CHRISTOS";
                else
                    preferredLabel = "IEDS_MEG_COMMON";
                end
                preferredIdx = find(upper(strtrim(candLabels))==preferredLabel);
                if isempty(preferredIdx)
                    candidatePool = (1:numel(candTimes))';
                else
                    candidatePool = preferredIdx;
                end
                [closestOffset,nearest] = min(abs(candTimes(candidatePool)-trialMid));
                assert(closestOffset <= 0.060, ...
                    ['Chosen allowed MEG event is more than 60 ms from the ' ...
                     'History import center; inspect annotation times.']);
                chosen = candidatePool(nearest);
                eventTrialTime = candTimes(chosen);
                eventLabel = candLabels(chosen);
                eventAbs = importStart + (eventTrialTime - trialTime(1));
                maskTimeMismatch = abs(maskEventTime-eventTrialTime) > 2/fs;
                if maskTimeMismatch
                    fprintf(['  Trial%s: mask built at %.6f s; selected %s at %.6f s ' ...
                        '(History-centered). Regenerating labels at selected event.\n'], ...
                        trialID,maskEventTime,char(eventLabel),eventTrialTime);
                end

                targetTime = eventAbs + relativeTargetTime;
                sampleBounds = round(double(sFile.prop.times)*fs);
                firstSample = floor((targetTime(1)-0.01)*fs);
                lastSample = ceil((targetTime(end)+0.01)*fs);
                assert(firstSample>=sampleBounds(1) && ...
                    lastSample<=sampleBounds(2), ...
                    'Full window extends beyond original recording.');
                [Fraw,Traw] = in_fread(sFile,C,1, ...
                    [firstSample lastSample],megIdx);
                Traw = double(Traw(:));
                assert(size(Fraw,1)==numel(megIdx) && ...
                    size(Fraw,2)==numel(Traw), ...
                    'Raw channel or sample dimensions mismatch.');
                assert(numel(Traw)>=2 && all(diff(Traw)>0) && ...
                    min(targetTime)>=Traw(1) && max(targetTime)<=Traw(end), ...
                    'Raw read does not cover target time grid.');
                X = interp1(Traw,double(Fraw.'),targetTime(:),'linear').';
                assert(isequal(size(X),[numel(megIdx),N_TIME]) && ...
                    all(isfinite(X(:))), 'Signal resampling failed.');

                % Align the already-created native segmentation mask by name + time.
                seg = M.SegMask;
                assert(isfield(seg,'mask') && isfield(seg,'time') && ...
                    isfield(seg,'channelNames'),'Incomplete SegMask.');
                nativeMask = logical(seg.mask);
                segTime = double(seg.time(:));
                segNames = erase(string(seg.channelNames(:)),' ');
                assert(size(nativeMask,1)==numel(segNames) && ...
                    size(nativeMask,2)==numel(segTime), ...
                    'Native mask dimensions do not match mask metadata.');
                assert(numel(segTime)>1 && all(diff(segTime)>0) && ...
                    abs(segTime(1)-trialTime(1))<=2/fs && ...
                    abs(segTime(end)-trialTime(end))<=2/fs, ...
                    'Mask time does not agree with original trial time.');
                assert(numel(unique(segNames))==numel(segNames), ...
                    'Duplicate mask channel names.');
                [matched,segIdx] = ismember(megNames,segNames);
                assert(all(matched),'Some raw MEG channels are missing from mask.');

                % Rebuild labels at the CHOSEN allowed event, not the
                % possibly unrelated event used when SegMask was created.
                % Channel membership still comes from this trial's high-power
                % channels; the time extent comes from SegMask.timeWindow.
                assert(isfield(seg,'highPowerChannels') && ...
                    ~isempty(seg.highPowerChannels), ...
                    'High-power channel metadata missing; cannot rebuild safely.');
                assert(isfield(seg,'timeWindow') && ...
                    isnumeric(seg.timeWindow) && numel(seg.timeWindow)==2, ...
                    'SegMask.timeWindow missing or invalid.');
                timeWindow = double(seg.timeWindow(:)');
                assert(all(isfinite(timeWindow)) && timeWindow(1)<0 && ...
                    timeWindow(2)>0 && timeWindow(1)<timeWindow(2), ...
                    'Invalid segmentation time window.');
                hpNames = upper(erase(strtrim(string(seg.highPowerChannels(:))),' '));
                hpNames = hpNames(hpNames~="");
                assert(~isempty(hpNames), 'No valid high-power channels.');
                megClean = upper(erase(strtrim(megNames(:)),' '));
                selectedMEG = ismember(megClean,hpNames);
                assert(any(selectedMEG), 'High-power channels not present in raw MEG.');

                % Exact time mapping: absolute raw time -> trial time.
                queryTrialTime = trialTime(1) + (targetTime(:)-importStart);
                selectedTime = queryTrialTime >= eventTrialTime+timeWindow(1) & ...
                    queryTrialTime <= eventTrialTime+timeWindow(2);
                Y = selectedMEG(:) & selectedTime(:)';
                assert(isequal(size(Y),[numel(megIdx),N_TIME]), ...
                    'Rebuilt mask has wrong dimensions.');

                % Identical shared spatial map for both data and labels.
                X234 = single(X(mapIdx,:));
                Yseg234 = logical(Y(mapIdx,:));
                assert(isequal(size(X234),[234 N_TIME]) && ...
                    isequal(size(Yseg234),[234 N_TIME]), ...
                    'Final X/Y shape mismatch.');
                assert(nnz(Yseg234)>0, ...
                    'Segmentation mask became empty after channel mapping.');

                % Distinct output IDs preserve subject/folder/trial identity.
                outName = sprintf('%s_%s_Trial%s_aligned_234.mat', ...
                    subject,folderName,trialID);
                outPath = fullfile(outFolder,outName);
                channelNames234 = mapNames;
                spikeTime = eventAbs;
                originalFs = fs;
                sourceBst = bstPath;
                trialSource = trialPath;
                maskSource = maskPath;
                save(outPath,'X234','Yseg234','channelNames234', ...
                    'relativeTargetTime','spikeTime','originalFs', ...
                    'sourceBst','trialSource','maskSource','-v7.3');
                numberSaved = numberSaved+1;
                records(end+1,:) = {subject,folderName,trialID,outName, ...
                    sourceBst,spikeTime,originalFs,nnz(Yseg234),234};
                fprintf('  OK Trial%s | %s | Fs %.3f | X/Y 234x1024 | %d positive pixels\n', ...
                    trialID,char(eventLabel),fs,nnz(Yseg234));
            catch ME
                failures(end+1,:) = {subject,folderName,trialID,ME.message};
                fprintf('  SKIP Trial%s: %s\n',trialID,ME.message);
            end
        end
    end
end

manifest = cell2table(records,'VariableNames', ...
    {'Subject','IEDFolder','Trial','OutputFile','SourceBST', ...
     'SpikeTimeSeconds','OriginalFs','PositivePixels','Channels'});
issues = cell2table(failures,'VariableNames', ...
    {'Subject','IEDFolder','Trial','Reason'});
writetable(manifest,fullfile(outFolder,'pairing_manifest.csv'));
writetable(issues,fullfile(outFolder,'failures.csv'));
fprintf('\nDONE: %d aligned pairs saved; %d issues.\n', ...
    numberSaved,height(issues));
fprintf('Output folder: %s\n',outFolder);
fprintf('Review pairing_manifest.csv and failures.csv before training.\n');
