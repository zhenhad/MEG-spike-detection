%% ==========================================================
%  SEGMENTATION MASK VISUALIZATION (Fig.3 style)
%  One trial only
%% ==========================================================

clear; clc; close all;

%% ------------------------------------------------------------------------
% Paths
%% ------------------------------------------------------------------------
dataDir = '\\192.168.0.101\papadelis_raid_02\Hmayag\MEEG_Simulations\data\BCH001\IEDs_MEG_Christos';

trialName = 'data_IEDs_MEG_Christos_trial001.mat';

channelFile = fullfile(dataDir,'channel_vectorview306_acc1.mat');

%% ------------------------------------------------------------------------
% Load Brainstorm files
%% ------------------------------------------------------------------------
S = load(fullfile(dataDir,trialName));

C = load(channelFile);

Channel = C.Channel;

%% ------------------------------------------------------------------------
% MEG channel names
%% ------------------------------------------------------------------------
channelNames = string({Channel.Name});

%% ------------------------------------------------------------------------
% High power channels
%% ------------------------------------------------------------------------
highPower = string(S.high_power_channel_names);

%% ------------------------------------------------------------------------
% Keep only MEG channels
%% ------------------------------------------------------------------------
isMEG = startsWith(channelNames,"MEG");

megNames = channelNames(isMEG);

F = S.F(isMEG,:);

nChannels = size(F,1);

Time = S.Time * 1000;      % ms

%% ------------------------------------------------------------------------
% Find spike time
%% ------------------------------------------------------------------------
eventTime = 0;

for k=1:length(S.Events)

    if strcmpi(S.Events(k).label,'IEDs_MEG_COMMON')

        eventTime = S.Events(k).times(1)*1000;

        break

    end

end

%% ------------------------------------------------------------------------
% Plot settings
%% ------------------------------------------------------------------------
spacing = 3;

figure('Color','w',...
       'Position',[100 50 500 1100]);

hold on

%% ------------------------------------------------------------------------
% Plot channels
%% ------------------------------------------------------------------------
for ch = 1:nChannels

    trace = F(ch,:);

    % Brainstorm-like normalization
    trace = trace - mean(trace);

    s = std(trace);

    if s>0
        trace = trace/s;
    end

    y0 = (nChannels-ch)*spacing;

    % entire trace (black)
    plot(Time,...
         trace+y0,...
         'k',...
         'LineWidth',0.6);

    % High power channels
    if any(megNames(ch)==highPower)

        idx = Time>=eventTime-60 & Time<=eventTime+60;

        plot(Time(idx),...
             trace(idx)+y0,...
             'Color',[0 0.85 0],...
             'LineWidth',1.8);

    end

end

%% ------------------------------------------------------------------------
% Cosmetics
%% ------------------------------------------------------------------------
xlim([eventTime-100 eventTime+100])

ylim([-spacing nChannels*spacing])

xlabel('Time (ms)','FontSize',12)

title('Trial 001','FontWeight','bold')

set(gca,...
    'YTick',[],...
    'Box','off',...
    'FontSize',11,...
    'LineWidth',1)

%% ------------------------------------------------------------------------
% Save MATLAB figure
%% ------------------------------------------------------------------------
savefig('Trial001_Fig3Style.fig')