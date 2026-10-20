root = '\\192.168.0.101\papadelis_raid_02\Hmayag\MEEG_Simulations\data';

trialFile = fullfile(root, 'BCH001', 'IEDs_MEG_Christos', ...
    'data_IEDs_MEG_Christos_trial001.mat');

rawFile = fullfile(root, 'BCH001', ...
    '@raw3950747_03_raw_notch', ...
    'data_0raw_3950747_03_raw_notch.mat')

channelFile = fullfile(root, 'BCH001', 'IEDs_MEG_Christos', ...
    'channel_vectorview306_acc1.mat');

%% Load trial and original recording link
S = load(trialFile);
R = load(rawFile, 'F');
C = load(channelFile);

sFile = R.F;

%% Display metadata
fprintf('\n=== ORIGINAL RECORDING ===\n');
fprintf('Binary file: %s\n', sFile.filename);
fprintf('File exists: %d\n', isfile(sFile.filename));
fprintf('Sampling rate: %.3f Hz\n', sFile.prop.sfreq);
fprintf('Recording range: %.6f to %.6f s\n', sFile.prop.times);

fprintf('\n=== TRIAL ===\n');
fprintf('Trial shape: %d channels x %d samples\n', size(S.F));
fprintf('Trial time range: %.6f to %.6f s\n', S.Time(1), S.Time(end));

disp('History source:');
disp(S.History{1,3});

disp('History annotation window:');
disp(S.History{3,3});

fprintf('\n=== EVENTS ===\n');
for k = 1:numel(S.Events)
    fprintf('%s: ', S.Events(k).label);
    fprintf('%.6f ', S.Events(k).times(:));
    fprintf('\n');
end

%% Read an example 1.024-second window
% Preliminary center: midpoint of the History import interval.
% We will verify the actual spike time before final extraction.

historyText = S.History{3,3};
numbers = regexp(historyText, ...
    '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', 'match');

assert(numel(numbers) >= 2, 'Cannot parse History time range.');

tStart = str2double(numbers{1});
tEnd   = str2double(numbers{2});
tCenter = (tStart + tEnd) / 2;

fs = sFile.prop.sfreq;
nSamples = round(1.024 * fs);

firstSample = round(tCenter * fs) - floor(nSamples / 2);
lastSample = firstSample + nSamples - 1;

recordBounds = round(sFile.prop.times * fs);

assert(firstSample >= recordBounds(1) && ...
       lastSample <= recordBounds(2), ...
       'Requested window is outside the recording.');

ChannelMat = C;

% Read only the first 5 channels for this diagnostic.
iChannels = 1:5;

[Ftest, Ttest] = in_fread( ...
    sFile, ChannelMat, 1, ...
    [firstSample lastSample], iChannels);

fprintf('\n=== RAW READ TEST ===\n');
fprintf('Read shape: %d channels x %d samples\n', size(Ftest));
fprintf('Read time: %.6f to %.6f s\n', Ttest(1), Ttest(end));
fprintf('Preliminary center: %.6f s\n', tCenter);

figure;
plot(Ttest, Ftest(1,:));
xlabel('Time (s)');
ylabel('MEG signal');
title('BCH001 Trial001: original continuous recording');
grid on;

%% Extract and resample one spike window

% Target: 1024 samples at 1000 Hz, centered on the spike
targetFs = 1000;
targetTime = tCenter + (-512:511) / targetFs;

% Read enough original samples to cover the target interval
firstSample = floor((targetTime(1) - 0.01) * fs);
lastSample  = ceil((targetTime(end) + 0.01) * fs);

% Read all MEG channels
isMEG = startsWith(string({C.Channel.Name}), "MEG");
megIdx = find(isMEG);

[Fraw, Traw] = in_fread( ...
    sFile, C, 1, [firstSample lastSample], megIdx);

% Resample onto the exact 1000-Hz time grid
X = interp1(Traw(:), Fraw.', targetTime(:), 'linear').';

assert(all(isfinite(X(:))), 'Resampling produced invalid values.');

fprintf('Original sampling rate: %.3f Hz\n', fs);
fprintf('Original window: %d channels x %d samples\n', size(Fraw));
fprintf('Resampled window: %d channels x %d samples\n', size(X));
fprintf('Spike center: %.6f s\n', tCenter);

%% Align BCH001 Trial001 segmentation mask with X

maskFile = fullfile(root, 'BCH001', 'IEDs_MEG_Christos', ...
    'HighPowerMasks', ...
    'data_IEDs_MEG_Christos_trial001_HighPowerMask.mat');

M = load(maskFile, 'SegMask');
seg = M.SegMask;

% Original mask and metadata
mask = logical(seg.mask);
maskTime = seg.time(:);
maskNames = string(seg.channelNames(:));

% Match channels by NAME, not by row number
rawNames = string({C.Channel(megIdx).Name})';

assert(size(mask,1) == numel(maskNames), ...
    'Mask channel count does not match channel names.');

[matched, loc] = ismember( ...
    erase(rawNames, " "), erase(maskNames, " "));

assert(all(matched), 'Some raw MEG channels are missing from mask.');

% Convert the 1024-sample timeline to trial-relative time
relativeTime = targetTime(:) - tCenter;

% Nearest-neighbor interpolation preserves binary labels
alignedMask = interp1( ...
    maskTime, double(mask'), relativeTime, 'nearest', 0)';

% Reorder mask channels to match X
Yseg = logical(alignedMask(loc,:));

assert(isequal(size(X), size(Yseg)), ...
    'X and Yseg dimensions do not match.');
assert(nnz(Yseg) > 0, 'Aligned segmentation mask is empty.');

fprintf('\n=== ALIGNMENT CHECK ===\n');
fprintf('X: %d x %d\n', size(X));
fprintf('Yseg: %d x %d\n', size(Yseg));
fprintf('Positive mask pixels: %d\n', nnz(Yseg));
fprintf('Matched channels: %d\n', sum(matched));

figure;
imagesc(relativeTime * 1000, 1:size(Yseg,1), Yseg);
xlabel('Time relative to spike (ms)');
ylabel('MEG channel');
title('BCH001 Trial001: aligned segmentation mask');
colorbar;

%% Apply the shared 234-channel map

mapFile = fullfile(root, '..', 'FAMED_channel_map_234.mat');
M = load(mapFile, 'chosenNames');

% Match by channel name, ignoring spaces
mapNames = erase(string(M.chosenNames(:)), " ");
rawNamesClean = erase(rawNames(:), " ");

[found, idx] = ismember(mapNames, rawNamesClean);

assert(all(found), 'Some mapped channels are missing.');
assert(numel(unique(idx)) == 234, 'Duplicate channel mapping.');

% Apply identical channel selection to signal and mask
X234 = single(X(idx, :));
Yseg234 = logical(Yseg(idx, :));

assert(isequal(size(X234), [234 1024]));
assert(isequal(size(Yseg234), [234 1024]));

fprintf('\n=== FINAL MAPPING CHECK ===\n');
fprintf('X234: %d x %d\n', size(X234));
fprintf('Yseg234: %d x %d\n', size(Yseg234));
fprintf('Positive pixels: %d\n', nnz(Yseg234));

% Save this test sample
save('BCH001_Trial001_aligned_234.mat', ...
    'X234', 'Yseg234', 'mapNames', ...
    'targetTime', 'tCenter', '-v7.3');

figure;
imagesc(relativeTime * 1000, 1:234, Yseg234);
xlabel('Time relative to spike (ms)');
ylabel('Mapped MEG channel');
title('BCH001 Trial001: Final 234-channel segmentation mask');
colorbar;