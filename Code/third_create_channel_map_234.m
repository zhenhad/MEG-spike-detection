%% Build a shared 234-channel map for six subjects
clear; clc;

root = '\\192.168.0.101\papadelis_raid_02\Hmayag\MEEG_Simulations\data';

subjects = {'BCH001','BCH007','BCH009', ...
            'BCH010','BCH012','BCH017'};

folders = {'IEDs_MEG_Christos', ...
           'IEDs_MEG_COMMON_Giorgos'};

N_GROUPS = 78;

allNames = cell(numel(subjects),1);
allTypes = cell(numel(subjects),1);
allChannels = cell(numel(subjects),1);

%% Load channel definitions for each subject
for s = 1:numel(subjects)

    found = false;

    for f = 1:numel(folders)

        folder = fullfile(root,subjects{s},folders{f});

        if ~isfolder(folder)
            continue;
        end

        files = dir(fullfile(folder,'channel*.mat'));

        if numel(files) ~= 1
            continue;
        end

        C = load(fullfile(files(1).folder,files(1).name));

        names = string({C.Channel.Name})';
        types = string({C.Channel.Type})';

        isMEG = startsWith(names,"MEG");

        allNames{s} = erase(names(isMEG)," ");
        allTypes{s} = types(isMEG);
        allChannels{s} = C.Channel(isMEG);

        fprintf('%s: %d MEG channels\n', ...
            subjects{s},numel(allNames{s}));

        found = true;
        break;
    end

    assert(found,'Channel file missing for %s',subjects{s});
end

%% Identify channels shared across every subject
shared = allNames{1};

for s = 2:numel(subjects)
    shared = intersect(shared,allNames{s},'stable');
end

fprintf('\nShared channels: %d\n',numel(shared));

%% Identify complete groups of three
groupIDs = unique(extractBetween(shared,4,6),'stable');

validGroups = strings(0,1);

for g = 1:numel(groupIDs)

    group = groupIDs(g);

    triplet = "MEG" + group + ["1";"2";"3"];

    if all(ismember(triplet,shared))
        validGroups(end+1,1) = group;
    end
end

fprintf('Complete shared sensor groups: %d\n', ...
    numel(validGroups));

assert(numel(validGroups) >= N_GROUPS, ...
    'Fewer than 78 complete sensor groups.');

%% Calculate group centers using BCH001 geometry
referenceNames = allNames{1};
referenceChannels = allChannels{1};

positions = zeros(numel(validGroups),3);

for g = 1:numel(validGroups)

    triplet = "MEG" + validGroups(g) + ["1";"2";"3"];

    xyz = zeros(3,3);

    for k = 1:3

        idx = find(referenceNames == triplet(k),1);

        loc = referenceChannels(idx).Loc;

        xyz(k,:) = mean(loc,2)';
    end

    positions(g,:) = mean(xyz,1);
end

%% Farthest-point sampling for spatial coverage
selected = zeros(N_GROUPS,1);

% Begin with group farthest from the overall centroid
center = mean(positions,1);

dist = sum((positions-center).^2,2);

[~,selected(1)] = max(dist);

minDist = sum((positions-positions(selected(1),:)).^2,2);

for k = 2:N_GROUPS

    minDist(selected(1:k-1)) = -Inf;

    [~,selected(k)] = max(minDist);

    newDist = sum( ...
        (positions-positions(selected(k),:)).^2,2);

    minDist = min(minDist,newDist);
end

%% Create the final 234-channel list
chosenGroups = validGroups(selected);

chosenNames = strings(N_GROUPS*3,1);

for g = 1:N_GROUPS

    rows = (g-1)*3 + (1:3);

    chosenNames(rows) = ...
        "MEG" + chosenGroups(g) + ["1";"2";"3"];
end

%% Validate matching order and channel types
referenceIdx = zeros(numel(chosenNames),1);

for k = 1:numel(chosenNames)
    referenceIdx(k) = find(referenceNames == chosenNames(k),1);
end

referenceTypes = allTypes{1}(referenceIdx);

for s = 1:numel(subjects)

    [found,loc] = ismember(chosenNames,allNames{s});

    assert(all(found), ...
        'Missing selected channels for %s',subjects{s});

    assert(isequal(allTypes{s}(loc),referenceTypes), ...
        'Channel type mismatch for %s',subjects{s});
end

%% Save mapping
channelMap = table( ...
    (1:numel(chosenNames))', ...
    chosenNames, ...
    referenceTypes, ...
    'VariableNames', ...
    {'ChannelIndex','ChannelName','ChannelType'});

csvPath = fullfile(pwd,'FAMED_channel_map_234.csv');
matPath = fullfile(pwd,'FAMED_channel_map_234.mat');

writetable(channelMap,csvPath);

save(matPath, ...
    'chosenNames','chosenGroups', ...
    'channelMap','positions','selected', ...
    'subjects');

fprintf('\nCHANNEL MAP CREATED\n');
fprintf('Sensor groups: %d\n',numel(chosenGroups));
fprintf('Channels: %d\n',numel(chosenNames));
fprintf('CSV: %s\n',csvPath);
fprintf('MAT: %s\n',matPath);