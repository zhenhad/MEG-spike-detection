%% Check MEG channel consistency across six subjects
clear; clc;

root = '\\192.168.0.101\papadelis_raid_02\Hmayag\MEEG_Simulations\data';

subjects = {'BCH001','BCH007','BCH009', ...
            'BCH010','BCH012','BCH017'};

folders = {'IEDs_MEG_Christos', ...
           'IEDs_MEG_COMMON_Giorgos'};

inventory = table();
referenceNames = string.empty(0,1);
referenceTypes = string.empty(0,1);

for s = 1:numel(subjects)
    for f = 1:numel(folders)

        folder = fullfile(root, subjects{s}, folders{f});

        if ~isfolder(folder)
            continue;
        end

        channelFiles = dir(fullfile(folder, 'channel*.mat'));

        if numel(channelFiles) ~= 1
            fprintf('SKIP %s / %s: found %d channel files\n', ...
                subjects{s}, folders{f}, numel(channelFiles));
            continue;
        end

        C = load(fullfile(folder, channelFiles(1).name), 'Channel');

        names = string({C.Channel.Name})';
        types = string({C.Channel.Type})';

        isMEG = startsWith(names, "MEG");

        megNames = names(isMEG);
        megTypes = types(isMEG);

        fprintf('\n%s | %s\n', subjects{s}, folders{f});
        fprintf('MEG channels: %d\n', numel(megNames));

        if isempty(referenceNames)
            referenceNames = megNames;
            referenceTypes = megTypes;
            fprintf('Reference channel list established.\n');
        else
            fprintf('Same channel names and order: %d\n', ...
                isequal(megNames, referenceNames));

            fprintf('Same channel-name set: %d\n', ...
                isequal(sort(megNames), sort(referenceNames)));

            fprintf('Same channel types and order: %d\n', ...
                isequal(megTypes, referenceTypes));
        end

        T = table( ...
            repmat(string(subjects{s}),numel(megNames),1), ...
            repmat(string(folders{f}),numel(megNames),1), ...
            (1:numel(megNames))', ...
            megNames, megTypes, ...
            'VariableNames', ...
            {'Subject','Folder','Index','ChannelName','Type'});

        inventory = [inventory; T];
    end
end

assert(~isempty(inventory), 'No channel files were found.');

outFile = fullfile(pwd, 'MEG_channel_inventory.csv');
writetable(inventory, outFile);

fprintf('\nSaved inventory: %s\n', outFile);
fprintf('Total inventory rows: %d\n', height(inventory));

