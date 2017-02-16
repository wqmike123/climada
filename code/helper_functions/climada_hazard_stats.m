function hazard = climada_hazard_stats(hazard,return_periods,check_plot,fontsize)
% NAME:
%   climada_hazard_stats
% PURPOSE:
%   plot hazard intensity maps for different return periods, based on the
%   probabilistic (and historic) data set. On output, the statistics are
%   available, directly added to the hazard structure.
%
%   If called with the output hazard on subsequent calls, only the plotting
%   needs to be done (e.g. to further improve plots). I.e. to repeat
%   calculation of the maps, delete hazard.map
%
%   See also climada_IFC_plot for a local hazard intensity/frequency plot
%
%   NOTE: this code listens to climada_global.parfor for substantial speedup
%
%   previous call: e.g. climada_tc_hazard_set
% CALLING SEQUENCE:
%   climada_hazard_stats(hazard,return_periods,check_plot)
% EXAMPLE:
%   hazard=climada_hazard_stats
%   climada_hazard_stats(hazard,[],-1) % show historic events only
% INPUTS:
%   hazard: hazard structure, as generated by e.g. climada_tc_hazard_set
%       > prompted for if not given
% OPTIONAL INPUT PARAMETERS:
%   return_periods: vector containing the requested return periods
%       (default=[1 5 10 25 50 100 500 1000])
%   check_plot: default=1, draw the intensity maps for various return
%       periods for the full hazard set. Set=0 to omit plot
%       =-1: calculate and plot the return period maps based on historic
%       events only (needs hazard.orig_event_flag to exist)
%   fontsize: default =12
% OUTPUTS:
%   the field hazard.map is added to the hazard structure, with
%       map.return_period(rp_i): return period rp_i
%       map.intensity(rp_i,c_i): intensity for return period rp_i at centroid c_i
%           based either on all (check_plot>0) or only on historic events
% MODIFICATION HISTORY:
% Lea Mueller, muellele@gmail.com, 20110623
% David N. Bresch, david.bresch@gmail.com, 20130317 cleanup
% David N. Bresch, david.bresch@gmail.com, 20140411 fixed some non-TC issues
% David N. Bresch, david.bresch@gmail.com, 20150114, Octave compatibility for -v7.3 mat-files
% Lea Mueller, muellele@gmail.com, 20150607, change tc max int. value to 80 instead of 100m/s
% Lea Mueller, muellele@gmail.com, 20150607, add cross for San Salvador in plot, for San Salvador only
% Lea Mueller, muellele@gmail.com, 20150716, add landslides option (LS) with specific colormap, intensities from 0 to 1
% David N. Bresch, david.bresch@gmail.com, 20160527, complete overhaul, new field hazard.map
% David N. Bresch, david.bresch@gmail.com, 20160529, otherwise in colorscale selection fixed
% David N. Bresch, david.bresch@gmail.com, 20160529, new default return periods (6)
% David N. Bresch, david.bresch@gmail.com, 20161006, minimum thresholds set for some perils
% David N. Bresch, david.bresch@gmail.com, 20170202, parallelized
% David N. Bresch, david.bresch@gmail.com, 20170216, small issue in line 274 (not fixed yet)
%-

% init global variables
global climada_global
if ~climada_init_vars, return; end

% poor man's version to check arguments
if ~exist('hazard'        , 'var'), hazard         = []; end
if ~exist('return_periods', 'var'), return_periods = []; end
if ~exist('check_plot'    , 'var'), check_plot     = 1 ; end
if ~exist('fontsize'     , 'var'),  fontsize       = 12 ; end

% Parameters
%
% set default return periods
if isempty(return_periods'),return_periods = [10 25 50 100 500 1000];end

hazard=climada_hazard_load(hazard);

% check if based on probabilistic tc track set
if isfield(hazard,'orig_event_flag') && check_plot<0
    sel_event_pos=find(hazard.orig_event_flag);
else
    sel_event_pos=1:length(hazard.frequency);
end

hist_str='';if check_plot<0,hist_str='historic ';end
intensity_threshold = 0; % default
cmap = climada_colormap(hazard.peril_ID); % default
caxis_min=0;caxis_max=full(max(max(hazard.intensity))); % default
switch hazard.peril_ID
    case 'TC'
        intensity_threshold = 5;
        caxis_max = 100;
        xtick_    = caxis_max/5:caxis_max/5:caxis_max;
        cbar_str  = [hist_str 'wind speed (m/s)'];
    case 'TR'
        caxis_max = 300; %caxis_max = 500;
        xtick_    = caxis_max/5:caxis_max/5:caxis_max;
        cbar_str  = [hist_str 'rain sum (mm)'];
    case 'TS'
        caxis_max = 10;
        xtick_    = caxis_max/5:caxis_max/5:caxis_max;
        cbar_str  = [hist_str 'surge height (m)'];
    case 'MS'
        caxis_max = 3;
        xtick_    = caxis_max/5:caxis_max/5:caxis_max;
        cbar_str  = sprintf('%%s intensity (%s)',hist_str,hazard.peril_ID,hazard.units);
    case 'LS'
        caxis_max = 1;
        xtick_    = caxis_max/5:caxis_max/5:caxis_max;
        cbar_str  = sprintf('%s%s intensity (%s)',hist_str,hazard.peril_ID,hazard.units);
        cmap = flipud(climada_colormap(hazard.peril_ID));
    case 'WS'
        intensity_threshold = 5;
        caxis_max = 60;
        xtick_    = caxis_max/5:caxis_max/5:caxis_max;
        cbar_str  = [hist_str 'wind speed (m/s)'];
    case 'HS'
        intensity_threshold = 10;
        if ~isfield(hazard,'units'),hazard.units='Ekin';end
        caxis_min = 200;
        caxis_max = 2000;
        xtick_    = caxis_max/5:caxis_max/5:caxis_max;
        cbar_str  = sprintf('%s%s intensity (%s)',hist_str,hazard.peril_ID,hazard.units);
    case 'EQ'
        intensity_threshold = 1;
    otherwise
        % use default colormap, hence no cmap defined
        xtick_    = caxis_max/5:caxis_max/5:caxis_max;
        cbar_str  = sprintf('%s%s intensity (%s)',hist_str,hazard.peril_ID,hazard.units);
end

if ~isfield(hazard,'units'),hazard.units='';end

n_return_periods         = length(return_periods);
n_centroids              = size(hazard.intensity,2);

% calculation
% -----------

if ~isfield(hazard,'map')
        
    n_events=length(hazard.frequency);
    n_sel_event=length(sel_event_pos);
        
    nonzero_intensity=sum(hazard.intensity(sel_event_pos,:),1);
    nonzero_centroid_pos=find(nonzero_intensity);
    n_nonzero_centroids=length(nonzero_centroid_pos);
    map_intensity=zeros(n_return_periods,n_nonzero_centroids);
    
    intensity=hazard.intensity(sel_event_pos,nonzero_centroid_pos);
    frequency=hazard.frequency(sel_event_pos)*n_events/n_sel_event;
    
    fprintf('calculate hazard statistics: processing %i %sevents at %i (non-zero) centroids\n',n_sel_event,hist_str,n_nonzero_centroids);

    t0       = clock;
    if climada_global.parfor
        parfor centroid_i = 1:n_nonzero_centroids
            map_intensity(:,centroid_i)=LOCAL_map_intensity(intensity(:,centroid_i),intensity_threshold,frequency,return_periods);
        end % centroid_i
    else
        mod_step = 10; % first time estimate after 10 tracks, then every 100
        format_str='%s';
        for centroid_i = 1:n_nonzero_centroids
            map_intensity(:,centroid_i)=LOCAL_map_intensity(intensity(:,centroid_i),intensity_threshold,frequency,return_periods);
            
            if mod(centroid_i,mod_step)==0 % progress report
                mod_step = 100;
                if n_centroids>10000,mod_step=1000;end
                if n_centroids>100000,mod_step=10000;end
                t_elapsed = etime(clock,t0)/centroid_i;
                n_remaining = n_centroids-centroid_i;
                t_projected_sec = t_elapsed*n_remaining;
                if t_projected_sec<60
                    msgstr = sprintf('est. %3.0f sec left (%i/%i centroids)',t_projected_sec, centroid_i, n_centroids);
                else
                    msgstr = sprintf('est. %3.1f min left (%i/%i centroids)',t_projected_sec/60, centroid_i, n_centroids);
                end
                fprintf(format_str,msgstr); % write progress to stdout
                format_str=[repmat('\b',1,length(msgstr)) '%s']; % back to begin of line
            end
            
        end % centroid_i
        fprintf(format_str,''); % move carriage to begin of line
    end
    fprintf('processing %i non-zero centroids took %2.2f sec\n',n_nonzero_centroids,etime(clock,t0));
    
    hazard.map.intensity=spalloc(n_return_periods,n_centroids,ceil(n_return_periods*n_nonzero_centroids)); % allocate
    hazard.map.intensity(:,nonzero_centroid_pos)=map_intensity;clear map_intensity % fill in
    hazard.map.return_period = return_periods;
    
end % calculation

% figures
% -------

if abs(check_plot)>0
    
    fprintf('plotting %sintensity vs return periods maps (be patient) ',hist_str)
    
    scale = max(hazard.lon)-min(hazard.lon);
    centroids.lon=hazard.lon; % to pass on below
    centroids.lat=hazard.lat; % to pass on below
    
    RP_count = length(return_periods);
    if RP_count < 3; y_no = RP_count; else y_no  = 3; end
    x_no         = ceil(RP_count/3);
    
    subaxis(x_no, y_no, 1,'MarginTop',0.15, 'mb',0.05)
    
    % colorbar
    subaxis(2);
    pos = get(subaxis(2),'pos');
    % distance in normalized units from the top of the axes
    dist = .06;
    hc = colorbar('location','northoutside', 'position',[pos(1) pos(2)+pos(4)+dist pos(3) 0.03]);
    set(get(hc,'xlabel'), 'String',cbar_str, 'fontsize',fontsize);
    caxis([caxis_min caxis_max])
    set(gca,'fontsize',fontsize)
    hold on
    
    for rp_i=1:n_return_periods
        
        fprintf('.') % simplest progress indicator
        subaxis(rp_i)
        
        values = full(hazard.map.intensity(rp_i,:));
        
        if sum(values(not(isnan(values))))>0 % nansum(values)>0
            [X, Y, gridded_VALUE] = climada_gridded_VALUE(values, centroids);
            gridded_VALUE(gridded_VALUE<0.1) = NaN; % avoid tiny values
            contourf(X, Y, gridded_VALUE,200,'linecolor','none')
        else
            text(mean([min(hazard.lon) max(hazard.lon)]),...
                mean([min(hazard.lat ) max(hazard.lat )]),...
                'no data for this return period available','fontsize',10,...
                'HorizontalAlignment','center')
        end
        hold on
        climada_plot_world_borders(2,'','',0,[],[0 0 0])
        title([int2str(hazard.map.return_period(rp_i)) ' yr'],'fontsize',fontsize);
        axis([min(hazard.lon)-scale/30  max(hazard.lon)+scale/30 ...
            min(hazard.lat )-scale/30  max(hazard.lat )+scale/30])
        % do not display xticks, nor yticks
        set(subaxis(rp_i),'xtick',[],'ytick',[],'DataAspectRatio',[1 1 1])
        caxis([0 caxis_max])
        if ~exist('cmap','var'), cmap = '';end
        if ~isempty(cmap), colormap(cmap);end
        set(gca,'fontsize',fontsize)
        set(hc,'XTick',xtick_)
        
    end % rp_i
    
    set(gcf,'Position',[427 29 574 644]);
    drawnow
    fprintf(' done\n')
    
end % figures

end % climada_hazard_stats

function map_intensity=LOCAL_map_intensity(intensity,intensity_threshold,frequency,return_periods)
[intensity_pos,ind_int] = sort(intensity,'descend');
if sum(intensity_pos)>0 % otherwise no intensity above threshold
    frequency2 = frequency;
    intensity_pos              = full(intensity_pos);
    below_thresh_pos           = intensity_pos<intensity_threshold;
    intensity_pos(intensity_pos<intensity_threshold) = [];
    frequency2 = frequency2(ind_int); % sort frequency accordingly
    frequency2(below_thresh_pos) = [];
    freq            = cumsum(frequency2(1:length(intensity_pos)))'; % exceedence frequency
    if length(freq)>1
        p           = polyfit(log(freq), intensity_pos, 1);
    else
        p = zeros(2,1);
    end
    exc_freq      = 1./return_periods;
    intensity_fit = polyval(p, log(exc_freq));
    intensity_fit(intensity_fit<=0)    = 0; %nan;
    R                                  = 1./freq;
    try
        neg                                = return_periods >max(R);
    catch
        map_intensity=zeros(length(return_periods),1);
        return
    end
    intensity_fit(neg)                 = 0; %nan;
    map_intensity = intensity_fit;
else
    map_intensity=zeros(length(return_periods),1);
end % sum(intensity_pos)>0 %
end % LOCAL_map_intensity