function GNeskeStimulusInNoise_PD_FullSynch_Psych_Spike2

%#ok<*MSNU>
global bQuit;
global cFlag;

fprintf('G Neske Stimulus In Noise.\n');

%Reward Parameters
ITIDuration = 120; %frames (2 s)
StimDuration = 90; %frames (1.5 s)
%Note that PreStimDuration varies on each trial, and is handled below
RewardDuration = 4; %frames (0.05 s, gives 4.5 uL per pulse on Box A)
TimeoutDurationFalseAlarm = 720; %frames (12 s)
TimeoutDurationMiss = 120; %frames (2 s)
waterPulseDuration = (4/60)*1000; %in milliseconds
safeLickDuration = ITIDuration - 12; %frames (12 = 0.2 s)
sanctuaryTime = 0; %frames


%Constants for identifying output type
waterReward = 1;
%Lick Enums
NoLickEvent = 0;
LickStarted = 1;
LickEnded = 2;

%State Enums
STATE_ITI = 0;
STATE_STIM = 1;
STATE_REWARD = 2;
STATE_PRESTIM = 3;
STATE_TIMEOUT = 4;

currentState = STATE_ITI; %set current state

%Number of trials before ending session
numTrials = 30;
trialNum = 1; %Set current trial number

commandwindow;
PsychDefaultSetup(1);
cFlag = '';
bQuit = false;
Init();
%%Reflective Mode has the Arduino reflect messages back to the sender.
bReflective = false;
%%Paired Mode has the Arduino initiate communication with another Arduino.
bPaired = false;
%Initiate the Serial Device and pass along the Property values.
SerialInit(bReflective,bPaired);
RegisterUpdate ( @MessageMonitor );
RegisterUpdate ( @RewardMonitor );
%%RegisterUpdate ( @SoundMonitor );

%Set up spacebar to end experiment
stopkey = KbName('space');
%Disable key output to Matlab window
ListenChar(2);

%%%%Upload all image files

%%Upload the gray screens
grayScreen = imread('grayScreen.jpg');

%%Upload the pre-stimulus sequences

%Upload the 4 different Pre-Stimulus noise sequences
preStimBlackCorner = cell(4,90);
for i = 1 : 4
    for j = 1 : 90
        preStimBlackCorner{i,j} = imread(strcat('preStimulusSequence', num2str(i),'Black', num2str(j), '.jpg'));
    end
end

%%Upload the stimulus sequences

%Upload the 4 different stimulus-in-noise varities, each of which
%contains a drifting grating embedded in one of the pre-stimulus noise
%sequences.  Do this for each of the 5 grating contrasts
stimWhiteCorner1 = cell(4,90);
for i = 1 : 4
    for j = 1 : 90
        stimWhiteCorner1{i,j} = imread(strcat('stimulusSequence', num2str(i),'WhiteFirstContrast', num2str(j), '.jpg'));
    end
end

stimWhiteCorner2 = cell(4,90);
for i = 1 : 4
    for j = 1 : 90
        stimWhiteCorner2{i,j} = imread(strcat('stimulusSequence', num2str(i),'WhiteSecondContrast', num2str(j), '.jpg'));
    end
end

stimWhiteCorner3 = cell(4,90);
for i = 1 : 4
    for j = 1 : 90
        stimWhiteCorner3{i,j} = imread(strcat('stimulusSequence', num2str(i),'WhiteThirdContrast', num2str(j), '.jpg'));
    end
end

stimWhiteCorner4 = cell(4,90);
for i = 1 : 4
    for j = 1 : 90
        stimWhiteCorner4{i,j} = imread(strcat('stimulusSequence', num2str(i),'WhiteFourthContrast', num2str(j), '.jpg'));
    end
end

stimWhiteCorner5 = cell(4,90);
for i = 1 : 4
    for j = 1 : 90
        stimWhiteCorner5{i,j} = imread(strcat('stimulusSequence', num2str(i),'WhiteFifthContrast', num2str(j), '.jpg'));
    end
end

%%Import array indicating the length (in frames) of the pre-stimulus period
%%for each trial
preStimDurs = cell2mat(struct2cell(load('preStimDurations.mat')));

%%Import array that will indicate which Pre-Stimulus sequences are to be presented every
%%120 frames during the Pre-Stimulus period for each trial.
preStimType = cell2mat(struct2cell(load('noiseIndexList.mat')));

%%Import array that will indicate which stimulus-in-noise sequence is to be presented 
%%during the stimulus (target) period at the end of each trial.
stimType = cell2mat(struct2cell(load('stimulusIndexList.mat')));

%%Import array that will indicate the contrast of the grating in the target
%%period at the end of each trial.
stimContrast = cell2mat(struct2cell(load('stimulusContrastList.mat')));

%%Import array that will dictate the length of the TTL pulses (for
%%synchronizing with camera software) that will be used during the session.
%%The length of synch pulses is in units of frames, and they occur
%%irregularly with lengths 1, 1.5, 2, and 2.5 s.
synchPulseList = cell2mat(struct2cell(load('synchPulseList.mat')));


PsychDefaultSetup(2);

Screen('Preference', 'SkipSyncTests', 1)

screens = Screen('Screens');
%Choose the non-primary monitor
screenNumber = max(screens);

[window, ~] = PsychImaging('OpenWindow', screenNumber);

%Measure vertical refresh rate of monitor
ifi = Screen('GetFlipInterval', window);

vblTimestamp = GetSecs;

%frameTimes is a 3xN matrix, where N is the number of frames presented
%during the entire session and each row has the trial number as the first
%index, the state type as the second index (ITI = 0, STIM = 1, REWARD = 2,
%PRESTIM = 3, TIMEOUT = 4), and the estimated presentation time of the
%frame as the third index
frameTimes = [];

%Define number of frames to wait in between stimulus presentations (should
%always be 1)
waitFrames = 1;

%Get maximum priority number
topPriorityLevel = MaxPriority(window);

Priority(topPriorityLevel);

try
fprintf('Arduino Initialized\n\n');

frame = 0;

progressTime = frame + ITIDuration;

currentlyLicking = false;

%synchPulse is updated to send an alternating digital pulse to synchronize
%with camera software.  The first pulse is positive.
synchPulse = 1;

%lickTimes is a 3xN matrix, where N is the number of licks detected
%during the entire session and each row has the trial number as the first
%index, the state type as the second index (ITI = 0, STIM = 1, REWARD = 2,
%PRESTIM = 3, TIMEOUT = 4), and the lick time as the third index
lickTimes = [];

%crTimes is a 3xN matrix, where N is the total number of correct rejections
%made during the entire session and each row has the trial number as the
%first index, the time at which the correct rejection was made as the
%second index, and the onset time of the preceding noise movie as the third
%index
crTimes = [];

%faTimes is a 3xN matrix, where N is the total number of false alarms made
%during the entire session and each row has the trial number as the first
%index, the time at which the false alarm was made as the second index,
%and the onset time of the preceding noise movie as the third index
faTimes = [];

%crTimes is a 3xN matrix, where N is the total number of misses
%made during the entire session and each row has the trial number as the
%first index, the contrast of the target when the miss was made as the 
%second index, and the time at which the miss was made as the third index
missTimes = [];

%hitTimes is a 4xN matrix, where N is the total number of hits made during
%the entire session and each row has the trial number as the first index,
%the contrast of the target when the hit was made as the second index, the
%time as which the hit occurred as the third index, and the target onset
%time as the fourth index
hitTimes = [];

falseAlarms = [];

correctRejections = [];

hitsContrast1 = [];

hitsContrast2 = [];

hitsContrast3 = [];

hitsContrast4 = [];

hitsContrast5 = [];

missesContrast1 = [];

missesContrast2 = [];

missesContrast3 = [];

missesContrast4 = [];

missesContrast5 = [];

preStimPeriodFrameNum = 0;

stimPeriodFrameNum = 0;

whichNoise = 1;

synchPulseLengthCheck = 1; %%synchPulseCheck is updated by 1 after the presentation of each frame

synchPulseIndex = 1;

currentSynchPulseLength = synchPulseList(synchPulseIndex);


while 1
    lickEvent = NoLickEvent;
        %%Call This every loop to update any messages
        Looper();
        %Looper is equivalent to:
        %  MessageMonitor(deltaT);
        %  RewardMonitor(delatT);
        %where deltaT is the time since the last frame
        
        %%Quit if Space was pressed
        [keyIsDown, secs, keyCode] = KbCheck;
        if (keyCode(stopkey))
            break;
        end
        
        %%Handle synch pulse updating here%%
        if synchPulseLengthCheck > currentSynchPulseLength
            
            if synchPulseIndex >= length(synchPulseList)
                synchPulseIndex = 1; %%If the number of synch pulses in the session has surpassed the number
                %alloted in synchPulseList, simply restart synch pulses from
                %beginning of synchPulseList
            else
                synchPulseIndex = synchPulseIndex + 1;
            end
            
            currentSynchPulseLength = synchPulseList(synchPulseIndex);
            synchPulseLengthCheck = 1;
            
            if synchPulse == 1;
                synchPulse = 0;
            elseif synchPulse == 0;
                synchPulse = 1;
            end
            
        end
        
        if synchPulse == 1;
             SendMessage('B');
        else
             SendMessage('b');
        end
        
        %%%STATE MACHINE CODE%%%%
        
        %%%STATE ITI%%%
     if (currentState==STATE_ITI)
         
         bitMap = grayScreen;
            
            %Show the frame
            imageMatrix = bitMap(:,:,1);
            tex = Screen('MakeTexture', window, imageMatrix);
            Screen('DrawTexture', window, tex); %Draw the texture
            [vblTimestamp, stimOnset, ~, ~, ~] = Screen('Flip', window, vblTimestamp + (waitFrames - 0.5)*ifi); %Flip to texture 
            Screen('Close', [tex]);
            frameTimes = [frameTimes; trialNum, currentState, stimOnset];
            frame = frame + 1;
            synchPulseLengthCheck = synchPulseLengthCheck + 1;
            
            Looper();
        
            %Check for licking
            if ( ~strcmp(cFlag,'') )
                %display(cFlag);            
                if (strcmp(cFlag,'A'))
                    lickEvent = LickStarted;
                    lickTime = GetSecs;
                    if currentlyLicking == false
                        lickTimes = [lickTimes; trialNum, currentState, lickTime];
                    end
                    currentlyLicking = true;
                elseif (strcmp(cFlag,'a'))
                    lickEvent = LickEnded;
                    currentlyLicking = false;
                end
            end 
            
     
            %If the frame number has surpassed the sanctuary time, restart
            %the ITI
              if (frame > sanctuaryTime)
                if (lickEvent==LickStarted)
                    currentState=STATE_ITI;
                    progressTime = frame + ITIDuration;
                elseif (currentlyLicking==true)
                    progressTime = frame + ITIDuration;
                end
              end
        %Try progressing to the next state, unless it's the last trial, in
        %which case, end the loop
        if ( frame >= progressTime && trialNum ~= (numTrials+1))
          currentState = STATE_PRESTIM;
          progressTime = frame + preStimDurs(trialNum);
        elseif (frame >= progressTime && trialNum == (numTrials+1))
            break;
        end
        
     %%%STATE PRESTIM%%%%%%% 
     elseif (currentState == STATE_PRESTIM)
         
         %See if the pre-stimulus noise sequence needs to be updated.  The
         %sequence needs to be updated every 120 frames
         if (preStimPeriodFrameNum == 120)
             whichNoise = whichNoise + 1;
             preStimPeriodFrameNum = 0;
             correctRejections(end+1) = 1;
             crTimes = [crTimes; trialNum, stimOnset, noiseOnset];
         end
         
         %Check if the gray screen now needs to be presented.  It needs to
         %be presented after 90 frames (1.5 s) of pre-stimulus noise sequence
         if (preStimPeriodFrameNum >= 90)
            bitMap = grayScreen;
         else
             bitMap = preStimBlackCorner{preStimType(trialNum, whichNoise), preStimPeriodFrameNum+1};
         end
         
         %Show the frame
            imageMatrix = bitMap(:,:,1);
            tex = Screen('MakeTexture', window, imageMatrix);
            Screen('DrawTexture', window, tex); %Draw the texture
            [vblTimestamp, stimOnset, ~, ~, ~] = Screen('Flip', window, vblTimestamp + (waitFrames - 0.5)*ifi); %Flip to texture 
            Screen('Close', [tex]);
            frameTimes = [frameTimes; trialNum, currentState, stimOnset];
            frame = frame + 1;
            if preStimPeriodFrameNum == 0
                noiseOnset = stimOnset;
            end
            preStimPeriodFrameNum = preStimPeriodFrameNum + 1;
            synchPulseLengthCheck = synchPulseLengthCheck + 1;
            
            Looper();
       
       %Only check for and punish licking if the white noise movies are
       %currently being presented.
       if (preStimPeriodFrameNum < 90)    
         %Check for licking
            if ( ~strcmp(cFlag,'') )
                %display(cFlag);            
                if (strcmp(cFlag,'A'))
                    lickEvent = LickStarted;
                    lickTime = GetSecs;
                    if currentlyLicking == false
                        lickTimes = [lickTimes; trialNum, currentState, lickTime];
                        faTimes = [faTimes; trialNum, lickTime, noiseOnset];
                    end
                    currentlyLicking = true;
                elseif (strcmp(cFlag,'a'))
                    lickEvent = LickEnded;
                    currentlyLicking = false;
                end
            end  
            
          %If the mouse licked, proceed to Timeout
                if (lickEvent==LickStarted)
                    currentState=STATE_TIMEOUT;
                    progressTime = frame + TimeoutDurationFalseAlarm; 
                    preStimPeriodFrameNum = 0;
                    falseAlarms(end+1) = 1;
                    whichNoise = 1;
                elseif (currentlyLicking==true)
                    currentState=STATE_TIMEOUT;
                    progressTime = frame + TimeoutDurationFalseAlarm; 
                    preStimPeriodFrameNum = 0;
                    falseAlarms(end+1) = 1;
                    whichNoise = 1;
                end
       end
       
        %Try progressing to the next state
        if ( frame >= progressTime )
          currentState = STATE_STIM;
          progressTime = frame + StimDuration; 
          preStimPeriodFrameNum = 0;
          correctRejections(end+1) = 1;
          crTimes = [crTimes; trialNum, stimOnset, noiseOnset];
          whichNoise = 1;
        end
        
     %%%STATE STIM%%%%%%%   
     elseif (currentState == STATE_STIM)
         
       currentContrast = stimContrast(trialNum);
                   
        if (currentContrast == 1) 
       
           bitMap = stimWhiteCorner1{stimType(trialNum), stimPeriodFrameNum+1};
         
            %Show the frame
            imageMatrix = bitMap(:,:,1);
            tex = Screen('MakeTexture', window, imageMatrix);
            Screen('DrawTexture', window, tex); %Draw the texture
            [vblTimestamp, stimOnset, ~, ~, ~] = Screen('Flip', window, vblTimestamp + (waitFrames - 0.5)*ifi); %Flip to texture 
            Screen('Close', [tex]);
            frameTimes = [frameTimes; trialNum, currentState, stimOnset];
            frame = frame + 1;
            if stimPeriodFrameNum == 0
                targetOnset = stimOnset;
            end
            stimPeriodFrameNum = stimPeriodFrameNum + 1;
            synchPulseLengthCheck = synchPulseLengthCheck + 1;
            
            Looper();
        
            %Check for licking
            if ( ~strcmp(cFlag,'') )
                %display(cFlag);            
                if (strcmp(cFlag,'A'))
                    lickEvent = LickStarted;
                    lickTime = GetSecs;
                    hitTimes = [hitTimes; trialNum, currentContrast, lickTime, targetOnset];
                    if currentlyLicking == false
                        lickTimes = [lickTimes; trialNum, currentState, lickTime];
                    end
                    currentlyLicking = true;
                elseif (strcmp(cFlag,'a'))
                    lickEvent = LickEnded;
                    currentlyLicking = false;
                end
            end  
            
            %Neither reward nor punish licking during the first 100 ms of
            %the stimulus period
            if (frame > (progressTime - 84)) %90 frames - 6 frames = 84 frames
                if (lickEvent==LickStarted)
                    currentState=STATE_REWARD;
                    hitsContrast1(end+1) = 1;
                    stimPeriodFrameNum = 0;
                elseif (currentlyLicking==true)
                    currentState=STATE_REWARD;
                    hitsContrast1(end+1) = 1;
                    stimPeriodFrameNum = 0;
                end
            end
        %Try progressing to the next state
        if ( frame >= progressTime )
          currentState = STATE_TIMEOUT;
          progressTime = frame + TimeoutDurationMiss;
          missesContrast1(end+1) = 1;
          missTimes = [missTimes; trialNum, currentContrast, stimOnset];
          stimPeriodFrameNum = 0;
        end
        
        elseif (currentContrast == 2)
            
            bitMap = stimWhiteCorner2{stimType(trialNum), stimPeriodFrameNum+1};
         
            %Show the frame
            imageMatrix = bitMap(:,:,1);
            tex = Screen('MakeTexture', window, imageMatrix);
            Screen('DrawTexture', window, tex); %Draw the texture
            [vblTimestamp, stimOnset, ~, ~, ~] = Screen('Flip', window, vblTimestamp + (waitFrames - 0.5)*ifi); %Flip to texture 
            Screen('Close', [tex]);
            frameTimes = [frameTimes; trialNum, currentState, stimOnset];
            frame = frame + 1;
            if stimPeriodFrameNum == 0
                targetOnset = stimOnset;
            end
            stimPeriodFrameNum = stimPeriodFrameNum + 1;
            synchPulseLengthCheck = synchPulseLengthCheck + 1;
            
            Looper();
        
            %Check for licking
            if ( ~strcmp(cFlag,'') )
                %display(cFlag);            
                if (strcmp(cFlag,'A'))
                    lickEvent = LickStarted;
                    lickTime = GetSecs;
                    hitTimes = [hitTimes; trialNum, currentContrast, lickTime, targetOnset];
                    if currentlyLicking == false
                        lickTimes = [lickTimes; trialNum, currentState, lickTime];
                    end
                    currentlyLicking = true;
                elseif (strcmp(cFlag,'a'))
                    lickEvent = LickEnded;
                    currentlyLicking = false;
                end
            end  
            
            %Neither reward nor punish licking during the first 100 ms of
            %the stimulus period
            if (frame > (progressTime - 84)) %90 frames - 6 frames = 84 frames
                if (lickEvent==LickStarted)
                    currentState=STATE_REWARD;
                    hitsContrast2(end+1) = 1;
                    stimPeriodFrameNum = 0;
                elseif (currentlyLicking==true)
                    currentState=STATE_REWARD;
                    hitsContrast2(end+1) = 1;
                    stimPeriodFrameNum = 0;
                end
            end
        %Try progressing to the next state
        if ( frame >= progressTime )
          currentState = STATE_TIMEOUT;
          progressTime = frame + TimeoutDurationMiss;
          missesContrast2(end+1) = 1;
          missTimes = [missTimes; trialNum, currentContrast, stimOnset];
          stimPeriodFrameNum = 0;
        end
        
        elseif (currentContrast == 3)
            
         bitMap = stimWhiteCorner3{stimType(trialNum), stimPeriodFrameNum+1};
         
            %Show the frame
            imageMatrix = bitMap(:,:,1);
            tex = Screen('MakeTexture', window, imageMatrix);
            Screen('DrawTexture', window, tex); %Draw the texture
            [vblTimestamp, stimOnset, ~, ~, ~] = Screen('Flip', window, vblTimestamp + (waitFrames - 0.5)*ifi); %Flip to texture 
            Screen('Close', [tex]);
            frameTimes = [frameTimes; trialNum, currentState, stimOnset];
            frame = frame + 1;
            if stimPeriodFrameNum == 0
                targetOnset = stimOnset;
            end
            stimPeriodFrameNum = stimPeriodFrameNum + 1;
            synchPulseLengthCheck = synchPulseLengthCheck + 1;
            
            Looper();
        
            %Check for licking
            if ( ~strcmp(cFlag,'') )
                %display(cFlag);            
                if (strcmp(cFlag,'A'))
                    lickEvent = LickStarted;
                    lickTime = GetSecs;
                    hitTimes = [hitTimes; trialNum, currentContrast, lickTime, targetOnset];
                    if currentlyLicking == false
                        lickTimes = [lickTimes; trialNum, currentState, lickTime];
                    end
                    currentlyLicking = true;
                elseif (strcmp(cFlag,'a'))
                    lickEvent = LickEnded;
                    currentlyLicking = false;
                end
            end  
            
            %Neither reward nor punish licking during the first 100 ms of
            %the stimulus period
            if (frame > (progressTime - 84)) %90 frames - 6 frames = 84 frames
                if (lickEvent==LickStarted)
                    currentState=STATE_REWARD;
                    hitsContrast3(end+1) = 1;
                    stimPeriodFrameNum = 0;
                elseif (currentlyLicking==true)
                    currentState=STATE_REWARD;
                    hitsContrast3(end+1) = 1;
                    stimPeriodFrameNum = 0;
                end
            end
        %Try progressing to the next state
        if ( frame >= progressTime )
          currentState = STATE_TIMEOUT;
          progressTime = frame + TimeoutDurationMiss; 
          missesContrast3(end+1) = 1;
          missTimes = [missTimes; trialNum, currentContrast, stimOnset];
          stimPeriodFrameNum = 0;
        end
        
        elseif (currentContrast == 4)
            
           bitMap = stimWhiteCorner4{stimType(trialNum), stimPeriodFrameNum+1};
         
            %Show the frame
            imageMatrix = bitMap(:,:,1);
            tex = Screen('MakeTexture', window, imageMatrix);
            Screen('DrawTexture', window, tex); %Draw the texture
            [vblTimestamp, stimOnset, ~, ~, ~] = Screen('Flip', window, vblTimestamp + (waitFrames - 0.5)*ifi); %Flip to texture 
            Screen('Close', [tex]);
            frameTimes = [frameTimes; trialNum, currentState, stimOnset];
            frame = frame + 1;
            if stimPeriodFrameNum == 0
                targetOnset = stimOnset;
            end
            stimPeriodFrameNum = stimPeriodFrameNum + 1;
            synchPulseLengthCheck = synchPulseLengthCheck + 1;
            
            Looper(); 
        
            %Check for licking
            if ( ~strcmp(cFlag,'') )
                %display(cFlag);            
                if (strcmp(cFlag,'A'))
                    lickEvent = LickStarted;
                    lickTime = GetSecs;
                    hitTimes = [hitTimes; trialNum, currentContrast, lickTime, targetOnset];
                    if currentlyLicking == false
                        lickTimes = [lickTimes; trialNum, currentState, lickTime];
                    end
                    currentlyLicking = true;
                elseif (strcmp(cFlag,'a'))
                    lickEvent = LickEnded;
                    currentlyLicking = false;
                end
            end  
            
            %Neither reward nor punish licking during the first 100 ms of
            %the stimulus period
            if (frame > (progressTime - 84)) %90 frames - 6 frames = 84 frames
                if (lickEvent==LickStarted)
                    currentState=STATE_REWARD;
                    hitsContrast4(end+1) = 1;
                    stimPeriodFrameNum = 0;
                elseif (currentlyLicking==true)
                    currentState=STATE_REWARD;
                    hitsContrast4(end+1) = 1;
                    stimPeriodFrameNum = 0;
                end
            end
        %Try progressing to the next state
        if ( frame >= progressTime )
          currentState = STATE_TIMEOUT;
          progressTime = frame + TimeoutDurationMiss; 
          missesContrast4(end+1) = 1;
          missTimes = [missTimes; trialNum, currentContrast, stimOnset];
          stimPeriodFrameNum = 0;
        end
        
        elseif(currentContrast == 5)
            
           bitMap = stimWhiteCorner5{stimType(trialNum), stimPeriodFrameNum+1};
         
            %Show the frame
            imageMatrix = bitMap(:,:,1);
            tex = Screen('MakeTexture', window, imageMatrix);
            Screen('DrawTexture', window, tex); %Draw the texture
            [vblTimestamp, stimOnset, ~, ~, ~] = Screen('Flip', window, vblTimestamp + (waitFrames - 0.5)*ifi); %Flip to texture 
            Screen('Close', [tex]);
            frameTimes = [frameTimes; trialNum, currentState, stimOnset];
            frame = frame + 1;
            if stimPeriodFrameNum == 0
                targetOnset = stimOnset;
            end
            stimPeriodFrameNum = stimPeriodFrameNum + 1;
            synchPulseLengthCheck = synchPulseLengthCheck + 1;
            
            Looper();
        
            %Check for licking
            if ( ~strcmp(cFlag,'') )
                %display(cFlag);            
                if (strcmp(cFlag,'A'))
                    lickEvent = LickStarted;
                    lickTime = GetSecs;
                    hitTimes = [hitTimes; trialNum, currentContrast, lickTime, targetOnset];
                    if currentlyLicking == false
                        lickTimes = [lickTimes; trialNum, currentState, lickTime];
                    end
                    currentlyLicking = true;
                elseif (strcmp(cFlag,'a'))
                    lickEvent = LickEnded;
                    currentlyLicking = false;
                end
            end  
            
            %Neither reward nor punish licking during the first 100 ms of
            %the stimulus period
            if (frame > (progressTime - 84)) %90 frames - 6 frames = 84 frames
                if (lickEvent==LickStarted)
                    currentState=STATE_REWARD;
                    hitsContrast5(end+1) = 1;
                    stimPeriodFrameNum = 0;
                elseif (currentlyLicking==true)
                    currentState=STATE_REWARD;
                    hitsContrast5(end+1) = 1;
                    stimPeriodFrameNum = 0;
                end
            end
        %Try progressing to the next state
        if ( frame >= progressTime )
          currentState = STATE_TIMEOUT;
          progressTime = frame + TimeoutDurationMiss; 
          missesContrast5(end+1) = 1;
          missTimes = [missTimes; trialNum, currentContrast, stimOnset];
          stimPeriodFrameNum = 0;
        end
        end       
     
        
     elseif (currentState == STATE_REWARD)
          currentState = STATE_ITI;
          Reward(waterReward, waterPulseDuration);
          trialNum = trialNum + 1;
          display(trialNum);
          frame = 0; %Reset frame number for next trial
          stimPeriodFrameNum = 0; %Reset stimulus period frame number for next trial 
          progressTime = frame + ITIDuration + RewardDuration;
          sanctuaryTime = frame + safeLickDuration;
          synchPulseLengthCheck = synchPulseLengthCheck + 1;
          
     elseif (currentState == STATE_TIMEOUT)
         
          bitMap = grayScreen;
            
            %Show the frame
            imageMatrix = bitMap(:,:,1);
            tex = Screen('MakeTexture', window, imageMatrix);
            Screen('DrawTexture', window, tex); %Draw the texture
            [vblTimestamp, stimOnset, ~, ~, ~] = Screen('Flip', window, vblTimestamp + (waitFrames - 0.5)*ifi); %Flip to texture 
            Screen('Close', [tex]);
            frameTimes = [frameTimes; trialNum, currentState, stimOnset];
            frame = frame + 1;
            synchPulseLengthCheck = synchPulseLengthCheck + 1;
            
         Looper();
            
         %Check for licking
            if ( ~strcmp(cFlag,'') )
                %display(cFlag);            
                if (strcmp(cFlag,'A'))
                    lickEvent = LickStarted;
                    lickTime = GetSecs;
                    if currentlyLicking == false
                        lickTimes = [lickTimes; trialNum, currentState, lickTime];
                    end
                    currentlyLicking = true;
                elseif (strcmp(cFlag,'a'))
                    lickEvent = LickEnded;
                    currentlyLicking = false;
                end
            end  
         
         if ( frame >= progressTime )
          currentState = STATE_ITI;
          trialNum = trialNum + 1;
          display(trialNum);
          frame = 0; %Reset for next trial
          stimPeriodFrameNum = 0; %Reset for next trial
          progressTime = frame + ITIDuration; 
          sanctuaryTime = 0;
        end
  end
end
 
sca;

%csvwrite('64_1_Licks.csv', lickTimes)
%csvwrite('033116_Hits_Contrast1_Mouse64_2.csv', hitsContrast1)
%csvwrite('033116_Hits_Contrast2_Mouse64_2.csv', hitsContrast2)
%csvwrite('033116_Hits_Contrast3_Mouse64_2.csv', hitsContrast3)
%csvwrite('033116_Hits_Contrast4_Mouse64_2.csv', hitsContrast4)
%csvwrite('033116_Hits_Contrast5_Mouse64_2.csv', hitsContrast5)
%csvwrite('033116_Misses_Contrast1_Mouse64_2.csv', missesContrast1)
%csvwrite('033116_Misses_Contrast2_Mouse64_2.csv', missesContrast2)
%csvwrite('033116_Misses_Contrast3_Mouse64_2.csv', missesContrast3)
%csvwrite('033116_Misses_Contrast4_Mouse64_2.csv', missesContrast4)
%csvwrite('033116_Misses_Contrast5_Mouse64_2.csv', missesContrast5)
%csvwrite('033016_FalseAlarms_Mouse64_2.csv', falseAlarms)

%dlmwrite('062716_FrameTimes_Mouse65.txt', frameTimes, 'precision', '%.6f')

%dlmwrite('090216_LickTimes_Mouse351.txt', lickTimes, 'precision', '%.6f')

%dlmwrite('090216_CRTimes_Mouse351.txt', crTimes, 'precision', '%.6f')

%dlmwrite('090216_FATimes_Mouse351.txt', faTimes, 'precision', '%.6f')

%dlmwrite('090216_HitTimes_Mouse351.txt', hitTimes, 'precision', '%.6f')

%dlmwrite('090216_MissTimes_Mouse351.txt', missTimes, 'precision', '%.6f')

totalFAs = length(falseAlarms)

totalCRs = length(correctRejections)

totalHitsContrast1 = length(hitsContrast1)
totalHitsContrast2 = length(hitsContrast2)
totalHitsContrast3 = length(hitsContrast3)
totalHitsContrast4 = length(hitsContrast4)
totalHitsContrast5 = length(hitsContrast4)

grandTotalHits = totalHitsContrast1 + totalHitsContrast2 + totalHitsContrast3 + totalHitsContrast4 + totalHitsContrast5

totalMissesContrast1 = length(missesContrast1)
totalMissesContrast2 = length(missesContrast2)
totalMissesContrast3 = length(missesContrast3)
totalMissesContrast4 = length(missesContrast4)
totalMissesContrast5 = length(missesContrast5)

grandTotalMisses = totalMissesContrast1 + totalMissesContrast2 + totalMissesContrast3 + totalMissesContrast4 + totalMissesContrast5
 
FArate = totalFAs / (totalFAs + totalCRs)

HitrateContrast1 = totalHitsContrast1 / (totalHitsContrast1 + totalMissesContrast1)
dPrimeContrast1 = norminv(HitrateContrast1,0,1) - norminv(FArate,0,1)
critContrast1 = -((norminv(HitrateContrast1,0,1) + norminv(FArate,0,1))/2)


HitrateContrast2 = totalHitsContrast2 / (totalHitsContrast2 + totalMissesContrast2)
dPrimeContrast2 = norminv(HitrateContrast2,0,1) - norminv(FArate,0,1)
critContrast2 = -((norminv(HitrateContrast2,0,1) + norminv(FArate,0,1))/2)


HitrateContrast3 = totalHitsContrast3 / (totalHitsContrast3 + totalMissesContrast3)
dPrimeContrast3 = norminv(HitrateContrast3,0,1) - norminv(FArate,0,1)
critContrast3 = -((norminv(HitrateContrast3,0,1) + norminv(FArate,0,1))/2)


HitrateContrast4 = totalHitsContrast4 / (totalHitsContrast4 + totalMissesContrast4)
dPrimeContrast4 = norminv(HitrateContrast4,0,1) - norminv(FArate,0,1)
critContrast4 = -((norminv(HitrateContrast4,0,1) + norminv(FArate,0,1))/2)


HitrateContrast5 = totalHitsContrast5 / (totalHitsContrast5 + totalMissesContrast5)
dPrimeContrast5 = norminv(HitrateContrast5,0,1) - norminv(FArate,0,1)
critContrast5 = -((norminv(HitrateContrast5,0,1) + norminv(FArate,0,1))/2)




ListenChar(0);
WaitSecs(0.1);
%Serial Cleanup
SerialCleanup();
clear all;
catch myerr
    totalFAs = length(falseAlarms)
    
    totalCRs = length(correctRejections)

    totalHitsContrast1 = length(hitsContrast1);
    totalHitsContrast2 = length(hitsContrast2);
    totalHitsContrast3 = length(hitsContrast3);
    totalHitsContrast4 = length(hitsContrast4);
    totalHitsContrast5 = length(hitsContrast4);

    grandTotalHits = totalHitsContrast1 + totalHitsContrast2 + totalHitsContrast3 + totalHitsContrast4 + totalHitsContrast5

    totalMissesContrast1 = length(missesContrast1);
    totalMissesContrast2 = length(missesContrast2);
    totalMissesContrast3 = length(missesContrast3);
    totalMissesContrast4 = length(missesContrast4);
    totalMissesContrast5 = length(missesContrast5);

    grandTotalMisses = totalMissesContrast1 + totalMissesContrast2 + totalMissesContrast3 + totalMissesContrast4 + totalMissesContrast5;
 
    FArate = totalFAs / (totalFAs + totalCRs)

    HitrateContrast1 = totalHitsContrast1 / (totalHitsContrast1 + totalMissesContrast1)


    HitrateContrast2 = totalHitsContrast2 / (totalHitsContrast2 + totalMissesContrast2)
    

    HitrateContrast3 = totalHitsContrast3 / (totalHitsContrast3 + totalMissesContrast3)


    HitrateContrast4 = totalHitsContrast4 / (totalHitsContrast4 + totalMissesContrast4)


    HitrateContrast5 = totalHitsContrast5 / (totalHitsContrast5 + totalMissesContrast5)
    
    whichNoise
    
    preStimPeriodFrameNum

    sca;
    commandwindow;
    myerr
    myerr.message
    myerr.stack.line 
end
end