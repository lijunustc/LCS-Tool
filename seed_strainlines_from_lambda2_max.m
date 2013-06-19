% seed_strainlines_from_lambda2_max Seeding strainlines from lambda_2 maxima
%
% SYNTAX
% [strainlinePosition,hFigure] = seed_strainlines_from_lambda2_max(distance)
% [strainlinePosition,hFigure] = seed_strainlines_from_lambda2_max(distance,hyperbolicLcsMaxNo)
%
% INPUT ARGUMENTS
% distance: threshold distance for placement of lambda_2 maxima
% hyperbolicLcsMaxNo: Maximum number of hyperbolic LCSs to generate. If not
% specified, this number defaults to the flow resolution.
%
% EXAMPLES
% strainlinePosition = seed_strainlines_from_lambda2_max(.025);
% strainlinePosition = seed_strainlines_from_lambda2_max(.025,uint8(5));

function [strainlinePosition,hFigure] = seed_strainlines_from_lambda2_max(distance,varargin)

narginchk(1,2)

p = inputParser;
addRequired(p,'distance',@(distance)validateattributes(distance,{'double'},{'scalar','>',0}))
uint = {'uint8','uint16','uint32','uint64'};
doubleGyre = double_gyre;
flow = doubleGyre.flow;
flow = set_flow_resolution([251,126],flow);
flow = set_flow_timespan([0,20],flow);
flow = set_flow_ode_solver_options(odeset('relTol',1e-4),flow);

% domainEnlargement = .05;
% flow = set_flow_domain([[0,2]+diff([0,2])*domainEnlargement*[-1,1];[0,1]+diff([0,1])*domainEnlargement*[-1,1]],flow);

addOptional(p,'hyperbolicLcsMaxNo',prod(flow.resolution),@(hyperbolicLcsMaxNo)validateattributes(hyperbolicLcsMaxNo,uint,{'scalar','>',0}));

parse(p,distance,varargin{:})
distance = p.Results.distance;
hyperbolicLcsMaxNo = p.Results.hyperbolicLcsMaxNo;

strainline = doubleGyre.strainline;
clear('doubleGyre')

%% Compute λ₂ array
method.name = 'finiteDifference';
customEigMethod = false;
coupledIntegration = true;
[cgEigenvalue,cgEigenvector] = eig_cgStrain(flow,method,customEigMethod,coupledIntegration);

%% Plot λ₂ field
lambda2 = reshape(cgEigenvalue(:,2),fliplr(flow.resolution));
hFigure = figure;
hAxes = axes;
set(hAxes,'parent',hFigure)
set(hAxes,'NextPlot','add')
set(hAxes,'box','on')
set(hAxes,'DataAspectRatio',[1,1,1])
hImagesc = imagesc(flow.domain(1,:),flow.domain(2,:),log(lambda2));
set(hImagesc,'parent',hAxes)
axis(hAxes,'tight')
hColorbar = colorbar('peer',hAxes);
set(get(hColorbar,'xlabel'),'string','log(\lambda_2)')
drawnow

% %% Plot ξ₁ field
% xPos = linspace(flow.domain(1,1),flow.domain(1,2),flow.resolution(1));
% yPos = linspace(flow.domain(2,1),flow.domain(2,2),flow.resolution(2));
% quiver(xPos,yPos,reshape(cgEigenvector(:,1),fliplr(flow.resolution)),reshape(cgEigenvector(:,2),fliplr(flow.resolution)))

%% Compute hyperbolic LCSs seeded from λ₂ local maxima

% Array that records grid points where a strainline already exits
flagArray = false(size(lambda2));

deltaX = diff(flow.domain(1,:))/double(flow.resolution(1)-1);
deltaY = diff(flow.domain(2,:))/double(flow.resolution(2)-1);
xPos = linspace(flow.domain(1,1),flow.domain(1,2),flow.resolution(1)) - .5*deltaX;
yPos = linspace(flow.domain(2,1),flow.domain(2,2),flow.resolution(2)) - .5*deltaY;
gridPosition{1} = xPos;
gridPosition{2} = yPos;

cmap = colormap(hAxes);
cmap(end,:) = ones(3,1);
colormap(hAxes,cmap)

if deltaX ~= deltaY
    error('Cannot set distnace in units of grid points if deltaX ~= deltaY')
else
    distanceGridPoints = uint64(distance./deltaX);
end

strainlinePosition = cell(1,hyperbolicLcsMaxNo);

nHyperbolicLcs = 0;
odeSolverOptions = odeset('relTol',1e-4);
while nHyperbolicLcs < hyperbolicLcsMaxNo
    [nextLocalMax,loc] = find_next_local_max(lambda2,flagArray,distanceGridPoints);
    if isempty(nextLocalMax)
        break
    end
    initialPosition = [xPos(loc(2))+.5*deltaX,yPos(loc(1))+.5*deltaX];
    hInitialPosition = plot(initialPosition(1),initialPosition(2));
    set(hInitialPosition,'marker','o')
    set(hInitialPosition,'markerEdgeColor','k')
    set(hInitialPosition,'markerFaceColor','k')
    set(hInitialPosition,'markerSize',8)
    periodicBc = false(2,1);
    positionPos = integrate_line([0,strainline.maxLength],initialPosition,flow.domain,flow.resolution,periodicBc,cgEigenvector(:,1:2),odeSolverOptions);
    positionNeg = integrate_line([0,-strainline.maxLength],initialPosition,flow.domain,flow.resolution,periodicBc,cgEigenvector(:,1:2),odeSolverOptions);
    strainlinePosition{nHyperbolicLcs+1} = [flipud(positionNeg);positionPos(2:end,:)];
    hStrainline = plot(hAxes,strainlinePosition{nHyperbolicLcs+1}(:,1),strainlinePosition{nHyperbolicLcs+1}(:,2));
    set(hStrainline,'color','k')
    set(hStrainline,'lineWidth',2)
        
    % Flag grid cells intersection by strainline
    iFlagArray = line_grid_intersection(strainlinePosition{nHyperbolicLcs+1},gridPosition,distanceGridPoints);
    flagArray = flagArray | iFlagArray;
    
    CData = get(findobj(hAxes,'Type','image'),'CData');
    CData(flagArray) = max(CData(:));
    set(findobj(hAxes,'Type','image'),'CData',CData)
    drawnow
    
    nHyperbolicLcs = nHyperbolicLcs + 1;
end

% Remove empty elements of cell array
strainlinePosition = strainlinePosition(~cellfun(@(input)isempty(input),strainlinePosition));

function [nextLocalMax,nextPosition] = find_next_local_max(array,flagArray,distance)

%% Find all local maxima with a distance threshold
[localMax,position] = local_max2D_gridded(array,distance);
[localMax,sortIndex] = sort(localMax,'descend');
position = position(sortIndex,:);

%% Check if next local maximum overlaps with flagArray
idx = 1;
while idx <= numel(localMax)
    if ~flagArray(position(idx,1),position(idx,2))
        nextLocalMax = localMax(idx);
        nextPosition = position(idx,:);
        return
    end
    idx = idx + 1;
end

% No local maxima left; return empty arrays
nextLocalMax = [];
nextPosition = [];

function flagArray = line_grid_intersection(position,gridPosition,distanceGridPoints)

nX = numel(gridPosition{1});
nY = numel(gridPosition{2});
flagArray = false(nY,nX);

nPoints = size(position,1);

circleMask = circle_mask(distanceGridPoints);
sizeArray = [numel(gridPosition{2}),numel(gridPosition{1})];

gridDeltaX = mean(diff(gridPosition{1}));
gridDeltaY = mean(diff(gridPosition{2}));
if ~(gridDeltaX == gridDeltaY)
    warning([mfilename,':unequalGridSpace'],['Unequal deltaX (',num2str(gridDeltaX),') and deltaY (',num2str(gridDeltaY),').'])
end

for iPoint = 1:nPoints-1
    % Create sequence of points along line with spacing no larger than
    % grid spacing.
    deltaX = diff(position([iPoint,iPoint+1],1));
    deltaY = diff(position([iPoint,iPoint+1],2));
    segmentLength = hypot(deltaX,deltaY);
    nPointsSegment = ceil(segmentLength/gridDeltaX)+1;
    positionSegmentX = linspace(position(iPoint,1),position(iPoint+1,1),nPointsSegment);
    positionSegmentY = linspace(position(iPoint,2),position(iPoint+1,2),nPointsSegment);
    positionSegment = transpose([positionSegmentX;positionSegmentY]);
    for iPointSegment = 1:nPointsSegment
        xI = find(positionSegment(iPointSegment,1) < gridPosition{1},1)-1;
        if isempty(xI)
            xI = nX;
        end
        if xI == 0
            xI = 1;
        end
        yI = find(positionSegment(iPointSegment,2) < gridPosition{2},1)-1;
        if isempty(yI)
            yI = nY;
        end
        if yI == 0
            yI = 1;
        end
        centre = [yI,xI];
        circleMaskGlobal = centred_mask(centre,sizeArray,circleMask);
        flagArray = flagArray | circleMaskGlobal;
    end
end

% Locally largest element in 2D array.
%
% SYNTAX
% [c,i] = local_max2D_gridded(array,radius)
%
% EXAMPLE
% C = peaks;
% [c,i] = local_max2D_gridded(C,uint8(5));
% imagesc(C)
% hold on
% plot(i(:,2),i(:,1),'ko')

function [c,i] = local_max2D_gridded(array,radius)

validateattributes(array,{'numeric'},{'2d'})
validateattributes(radius,{'uint8','uint16','uint32','uint64'},{'scalar','>',0})

circle = circle_mask(radius);

c = nan(size(array));
i = false(size(array));

for m = 1:size(array,1)
    for n = 1:size(array,2)
        centredMask = centred_mask([m,n],size(array),circle);
        if ~any(array(m,n) < array(centredMask))
            c(m,n) = array(m,n);
            i(m,n) = true;
        end
    end
end

c = c(~isnan(c));
[row,col] = find(i);
i = [row,col];
