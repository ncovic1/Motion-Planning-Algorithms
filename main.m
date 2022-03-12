% close all;
clear;

set(groot,'defaulttextinterpreter','latex'); 
set(groot, 'defaultAxesTickLabelInterpreter','latex'); 
set(groot, 'defaultLegendInterpreter','latex');

global robot obstacles tree;

robot.dim       = 2;        % Robot dimensionality in workspace
robot.model     = 1;        % Model of robotic manipulator (See details in 'Initialization')
obstacles.model = 2;        % Model of obstacles (1: spherical, 2: boxed)
obstacles.type  = 4;        % See details bellow
obstacles.step  = 0.02;     % obstacles moves by the size of this step
Initialization;             % Initialization of the robot and obstacles
DrawRobot(robot.q_init, 'magenta', 0.3, 3, 20);     % The library 'geom3d' must be included for 3D robot. 
DrawRobot(robot.q_goal, 'green', 0.3, 3, 20);       % You can find it at https://github.com/mattools/matGeom
DrawObstacles(0.03);

% ALG = RRT();
% ALG = RRT_Connect();
% ALG = RBT();
% ALG = RGBT();
ALG = RGBMT_star(0.1, 1000, 0.01, 60);
ALG = ALG.Run();

DrawDetails(ALG.path, 0.1, 0);

% ALG = DRGBT();  ALG = ALG.Run();
% ALG = RRTx(0.1, 3000);
