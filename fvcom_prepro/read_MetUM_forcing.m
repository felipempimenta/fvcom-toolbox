function MetUM = read_MetUM_forcing(files, varlist)
% Read Met Office Unified Model (TM) (hereafter MetUM) netCDF files and
% extact the variables in varlist.
%
% MetUM = read_MetUM_forcing(files, varlist)
%
% DESCRIPTION:
%   Given a cell array of file names, extract the variables in varlist into
%   a struct. Field names are the variable names gives.
%
% INPUT:
%   files - cell array of file names (full paths to the files)
%   varlist [optional] - list of variable names to extract. If omitted, all
%   variables are extracted.
%
% OUTPUT:
%   MetUM - MATLAB struct with the data from the variables specified in
%   varlist.
%
% EXAMPLE USAGE:
%   varlist = {'x', 'y', 't_1', 'sh', 'x-wind', 'y-wind', 'rh', 'sh', ...
%       'lh', 'solar', 'longwave'};
%   files = {'/tmp/sn_2011010100_s00.nc', '/tmp/sn_201101016_s00.nc'};
%   MetUM = read_MetUM_forcing(files, varlist);
%
% NOTE:
%   The last 4 times are dropped from each file because the Met Office
%   Unified Model is a forecast model with four hours of forecast in these
%   PP files.
%
% Author(s):
%   Pierre Cazenave (Plymouth Marine Laboratory)
%
% Revision history:
%   2013-08-29 First version.
%   2013-09-02 Amend the way the 3 and 4D variables are appended to one
%   another. The assumption now is time is the last dimension and arrays
%   are appended with time.
%   2013-09-06 Trim the last 4 time samples from all variables (these are
%   the forecast results which we don't want/need for forcing the model. I
%   suppose at some point, given the patchy temporal coverage of the data
%   (i.e. the Met Office FTP server doesn't have all files in a usable
%   state), it might be better to use the forecast data to partially fill
%   in gaps from missing files. However, given this forcing is hourly and I
%   was previously using four times daily forcing, I'm not that fussed.
%
%==========================================================================

subname = 'read_MetUM_forcing';

global ftbverbose
if ftbverbose
    fprintf('\nbegin : %s \n', subname)
end

assert(iscell(files), 'List of files provided must be a cell array.')

MetUM = struct();

for f = 1:length(files)
    
    if ftbverbose
        fprintf('File %s... ', files{f})
    end

    nc = netcdf.open(files{f}, 'NOWRITE');
    
    % Query the netCDF file to file the variable names. If the name matches
    % one in the list we've been given (or if we haven't been given any
    % particular variables), save it in the output struct.
    [~, numvars, ~, ~] = netcdf.inq(nc);

    for ii = 1:numvars
        % Find the name of the current variable
        [varname, ~, ~, varAtts] = netcdf.inqVar(nc, ii - 1);

        if ismember(varname, varlist) || nargin == 1
            varid = netcdf.inqVarID(nc, varname);

            % Some variables contain illegal (in MATLAB) characters. Remove
            % them here.
            safename = regexprep(varname, '-', '');

            % Append the data on the assumption the last dimension is time.
            % Don't append data with only 2 dimensions as it's probably
            % longitude or latitude data. The time variable ('t') is
            % turned into a list of time stamps.
            tmpdata = squeeze(netcdf.getVar(nc, varid, 'double'));
            nn = ndims(tmpdata);

            if isfield(MetUM, safename)
                switch varname
                    case {'x', 'y', 'x_1', 'y_1', 'longitude', 'latitude'}
                        continue
                    case {'t', 't_1'}
                        % Get the time attribute so we can store proper
                        % times.
                        tt = fix_time(nc, varid, varAtts);
                        MetUM.(safename) = cat(1, MetUM.(safename), tt);
                    otherwise
                        try
                            % Append along last dimension.
                            MetUM.(safename) = cat(nn, MetUM.(safename), tmpdata(:, :, 1:end - 4));
                        catch
                            fprintf('\n')
                            warning('Couldn''t append %s to the existing field from file %s.', safename, files{f})
                        end

                end
            else % first time around
                switch varname
                    case {'x', 'y', 'x_1', 'y_1', 'longitude', 'latitude'}
                        MetUM.(safename) = tmpdata;
                    case {'t', 't_1'}
                        % Get the time attribute so we can store proper
                        % times.
                        MetUM.(safename) = fix_time(nc, varid, varAtts);
                    otherwise
                        MetUM.(safename) = tmpdata(:, :, 1:end - 4);
                end
            end
        end
    end

    if ftbverbose
        fprintf('done.\n')
    end

end

% Squeeze out singleton dimensions.
fields = fieldnames(MetUM);
for i = 1:length(MetUM)
    MetUM.(fields{i}) = squeeze(MetUM.(fields{i}));
end

if ftbverbose
    fprintf('end   : %s \n', subname)
end

function tt = fix_time(nc, varid, varAtts)
% Little helper function to get the time attribute so we can store proper
% times.
%
% INPUT:
%   nc : netCDF file handle
%   varid : current variable ID
%   varAtts : number of variable attributes
%
% OUTPUT:
%   tt : date string for the current file (Gregorian date)
%
for j = 1:varAtts
    timeatt = netcdf.inqAttName(nc, varid, j - 1);
    if strcmpi(timeatt, 'time_origin')
        timeval = netcdf.getAtt(nc, varid, timeatt);
    end
end
mt = datenum(timeval, 'dd-mmm-yyyy:HH:MM:SS');
% t is the offset in days relative to mt.
t = netcdf.getVar(nc, varid, 'double');
if isempty(t)
    % This isn't right. Might be easier to get the time from the file
    % name...
    t = 0;
end
% Add the offset and convert back to a date string.
tt = datestr(mt + t(1:end - 4), 'yyyy-mm-dd HH:MM:SS');
