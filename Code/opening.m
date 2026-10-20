%% ============================================================
% Display one annotated MEG trial with segmentation mask
% BCH001 - Trial001
%% ============================================================
clear;
clc;
close all;
% ------------------------------------------------------------------------
% File paths
folder = '\\192.168.0.101\papadelis_raid_02\Hmayag\MEEG_Simulations\data\BCH001\IEDs_MEG_Christos';
trialFile = 'data_IEDs_MEG_Christos_trial001.mat';
channelFile = fullfile(folder,'channel_vectorview306_acc1.mat');
% ------------------------------------------------------------------------
% Load files
S = load(fullfile(folder,trialFile));
C = load(channelFile);
% ------------------------------------------------------------------------
% Extract data
F = S.F;
Time = S.Time;
Channel = C.Channel;
channelNames = string({Channel.Name});
% ------------------------------------------------------------------------
% Keep only MEG channels
isMEG = startsWith(channelNames,"MEG");
channelNames = channelNames(isMEG);
F = F(isMEG,:);
nChannels = size(F,1);
% ------------------------------------------------------------------------
% Read high-power channel names
highPower = string(S.high_power_channel_names);
% ------------------------------------------------------------------------
% Find IED annotation
eventTime = [];

for k = 1:length(S.Events)

    if strcmp(S.Events(k).label,'IEDs_MEG_COMMON')

        eventTime = S.Events(k).times(1);

        break

    end

end

if isempty(eventTime)
    error('IEDs_MEG_COMMON event not found.');
end

fprintf('IED annotation = %.3f ms\n',eventTime*1000);

% ------------------------------------------------------------------------
% ±60 ms mask
timeMask = Time >= (eventTime-0.060) & ...
           Time <= (eventTime+0.060);

% ------------------------------------------------------------------------
% Figure
figure('Color','w',...
       'Position',[100 50 650 1000]);

ax = gca;

% Initial gain
gain = 1;

% Slider
uicontrol('Style','slider',...
          'Units','normalized',...
          'Position',[0.90 0.15 0.03 0.70],...
          'Min',0.2,...
          'Max',10,...
          'Value',1,...
          'Callback',@(src,evt) updateGain(src,ax));

hold on

spacing = 4;

% ------------------------------------------------------------------------
% Plot channels
for ch = 1:nChannels

    trace = F(ch,:);

    % Normalize only for display
    trace = trace - mean(trace);

    s = std(trace);

    if s>0
        trace = trace/s;
    end

    offset = (nChannels-ch)*spacing;

    % ----------------------------------------------------------
    % Entire trace in black
    % ----------------------------------------------------------
    plot(Time*1000,...
         trace+offset,...
         'k',...
         'LineWidth',0.5);

    % ----------------------------------------------------------
    % Highlight only high-power channels
    % ----------------------------------------------------------
    if any(channelNames(ch)==highPower)

        plot(Time(timeMask)*1000,...
             trace(timeMask)+offset,...
             'Color',[0 0.75 0],...
             'LineWidth',2);

    end

end
% ------------------------------------------------------------------------
% Show IED annotation

xline(eventTime*1000, ...
    '--r', ...
    'LineWidth', 2, ...
    'Label', 'IEDs\_MEG\_COMMON', ...
    'LabelOrientation', 'horizontal', ...
    'LabelVerticalAlignment', 'middle');
% ------------------------------------------------------------------------
% Cosmetics
xlabel('Time (ms)','FontSize',12)
ylabel('MEG Channels','FontSize',12)

title('BCH001 - Trial001','FontWeight','bold')

set(gca,...
    'YTick',[],...
    'Box','off',...
    'FontSize',11,...
    'LineWidth',1);

xlim([Time(1) Time(end)]*1000);

hold off

% ------------------------------------------------------------------------
% Save as a Brainstorm data file and register it
[sStudy, iStudy] = bst_get('StudyWithCondition','BCH001/IEDs_MEG_Christos');

OutputFile = fullfile(folder,...
    'data_IEDs_MEG_Christos_trial001_HighPowerMask.mat');

bst_save(OutputFile, Sout, 'v6');

db_add_data(iStudy, OutputFile, Sout);

panel_protocols('UpdateNode','Study',iStudy);
% Create a new Brainstorm data structure from the original trial
Sout = S;

% Keep the original data
Sout.F = S.F;

% Add your mask information
Sout.high_power_channel_names = highPower;
Sout.timeMask                 = timeMask;
Sout.eventTime                = eventTime;

% Change comment shown in Brainstorm
Sout.Comment = 'Trial001 HighPowerMask';

% Output filename
newFile = fullfile(folder,...
    'data_IEDs_MEG_Christos_trial001_HighPowerMask.mat');

% Save in Brainstorm format
bst_save(newFile, Sout, 'v6');

% -------------------------------------------------------------------------
% Register file in Brainstorm database

DataFile = db_template('Data');

DataFile.FileName = strrep(newFile, bst_get('BrainstormDbDir'), '');
DataFile.Comment  = Sout.Comment;
DataFile.DataType = Sout.DataType;
DataFile.Device   = Sout.Device;

db_add_data(iStudy, DataFile);

% Reload database
db_reload_database('current');

fprintf('\n-------------------------------------\n');
fprintf('Successfully added to Brainstorm:\n');
fprintf('%s\n', newFile);
fprintf('-------------------------------------\n');

function updateGain(src,ax)

gain = src.Value;

lines = findobj(ax,'Type','line');

for k = 1:length(lines)

    y = get(lines(k),'YData');

    yMean = mean(y);

    y = (y - yMean) * gain + yMean;

    set(lines(k),'YData',y);

end

drawnow

end