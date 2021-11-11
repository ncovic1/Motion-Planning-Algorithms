classdef RGBMT < RGBT
properties
    cost_opt = inf;     % The cost of the final path
    stopping_cond = 0;  % Stopping condition. 0: Maximal number of nodes is reached (default); 1: Initial path is found; 
    costs = [];
end

methods    
    function this = RGBMT(eps, N_max, d_crit, stopping_cond)
        if nargin > 0
            this.eps = eps;
            this.N_max = N_max;
            this.d_crit = d_crit;
            this.stopping_cond = stopping_cond;
        end
    end
    
    
    function this = Run(this)
        global robot tree graphics;      
        tree.nodes = {robot.q_init, robot.q_goal};  % Consisting of two parts, one from q_init and another from q_goal
        tree.pointers = {{0}, {0}};                 % Pointing to location of parent/children in trees
        tree.distances = {NaN, NaN};                % Distance to each obstacle for each node
        tree.planes = {{{NaN}}, {{NaN}}};           % Lines/planes dividing space into two subspaces (free and "occupied")
        tree.costs = {0, 0};                        % Cost-to-come for each node in corresponding tree
        TN_new = 3;                                 % The ordinal number of the new tree
        graphics = {line(0,0)};                     % For graphical representation of some algorithm details
        
        this.T_alg = tic;
        [tree.distances{1}(1), ~] = this.Get_dc_AndPlanes(1, 1);
        if tree.distances{1}(1) == 0
            disp('Initial robot configuration is in the collision!');
            return;
        end
        [tree.distances{2}(1), ~] = this.Get_dc_AndPlanes(2, 1);
        if tree.distances{2}(1) == 0
            disp('Goal robot configuration is in the collision!');
            return;
        end 
        
        while true            
            while true
                % If q_rand is collision-free, it is accepted
                q_rand = this.Get_q_rand();
                collision = CheckCollision(q_rand);                
                if ~collision
                    [d_c, planes] = GetDistance(q_rand);
                    break;
                end                
            end
            
            % Adding the new tree to 'tree'
            tree.nodes{TN_new} = q_rand;
            tree.pointers{TN_new} = {0};
            tree.distances{TN_new} = d_c;
            tree.planes{TN_new} = {planes};
            tree.costs{TN_new} = 0;
            Q_reached_p = zeros(1,TN_new-1);  % Pointers to reached nodes in other trees         
            trees_reached = [];               % List of reached trees
            trees_exist = [];                 % List of trees for which new tree is extended to
            
            % Considering all previous trees
            for TN = 1:TN_new-1     
                % If the connection with q_near is not possible, attempt to connect with parent(q_near), etc.
                [q_near, q_near_p] = GetNearestNode(tree.nodes{TN}, q_rand);                
                while true      
                    [reached, q_new] = this.ConnectNodes(TN_new, 1, q_near);    % q_rand to q_near
                    q_parent_p = tree.pointers{TN}{q_near_p}(1);
                    if reached || q_parent_p == 0
                        break;
                    else
                        q_near = tree.nodes{TN}(:,q_parent_p);
                        q_near_p = q_parent_p;
                    end
                end              
                
                % Whether currently considering tree is reached
                cost = this.GetCost(q_new, q_rand);
                if reached      
                    UpgradeTree(TN_new, 1, q_new, tree.distances{TN}(q_near_p), tree.planes{TN}{q_near_p}, cost);
                    Q_reached_p(TN) = q_near_p;
                    trees_reached = [trees_reached, TN];
                    trees_exist = [trees_exist, TN];
                elseif cost >= this.eps
                    UpgradeTree(TN_new, 1, q_new, NaN, NaN, cost);
                    trees_exist = [trees_exist, TN];
                end
            end   
            
            % Find the optimal edge towards each reached tree
            if ~isempty(trees_reached)
                % The connection of q_rand with both main trees exists
                TN0 = trees_reached(1);  % Considering main tree
                if length(trees_reached) > 1 && sum(trees_reached(1:2)) == 3    
                    if rand > size(tree.nodes{2},2)/(size(tree.nodes{1},2)+size(tree.nodes{2},2))   
                        TN0 = trees_reached(2);     % q_rand will be joined to the second main tree
                    end
                end
                                
                % Considering all edges from the new tree
                q_rand_p = this.OptimizeEdge(TN_new, 1, TN0, Q_reached_p(TN0)); % From q_rand to tree TN0                
                k = 1;  % Ordinal number of node from the new tree
                trees_connected = [];
                for TN = trees_exist  
                    k = k+1;
                    
                    if TN == TN0  % It was considered previously, so just skip now
                        continue;
                    end
                    
                    % Unifying of the tree TN with TN0. Main trees are never unified mutually
                    q_new_p = this.OptimizeEdge(TN_new, k, TN0, q_rand_p);  % From reached node to tree TN0  
                    if TN > 2 && any(TN == trees_reached)    
                        this.ConnectTrees(TN, Q_reached_p(TN), TN0, q_new_p);
                        trees_connected = [trees_connected, TN];
                        
                    % The connection of q_rand with both main trees exists
                    elseif TN < 3 && length(trees_reached) > 1 && sum(trees_reached(1:2)) == 3  
                        cost_new = tree.costs{TN0}(q_new_p) + tree.costs{TN}(Q_reached_p(TN));
                        if cost_new < this.cost_opt     % The optimal connection between main trees is stored
                            this.cost_opt = cost_new;   % disp(cost_new);
                            q1_joint_p = q_new_p;
                            q2_joint_p = Q_reached_p(TN);
                            TN_main = TN0;
                        end
                    end
                end
                
                % Deleting trees that are connected
                if ~isempty(trees_connected)  
                    this.DeleteTree(trees_connected);
                    TN_new = TN_new - length(trees_connected);
                end
            
            % If there is no reached trees, then the new one is added to 'tree'
            else
                TN_new = TN_new+1;
            end
            
            this.N_nodes = 0;
            for TN = 1:length(tree.nodes)
                this.N_nodes = this.N_nodes + size(tree.nodes{TN},2);
            end
            this.costs = [this.costs, this.cost_opt*ones(1,this.N_nodes-length(this.costs))];
            
            %%%%%%%%%%%% Drawing %%%%%%%%%%%%%%%
%             if this.cost_opt < inf
%                 this.path = GetPath(q1_joint_p, q2_joint_p, TN_main);
%             end
%             this.Draw();
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            
            if this.stopping_cond || (~this.stopping_cond && this.N_nodes >= this.N_max)
                this.DeleteTree(TN_new);
                if this.cost_opt < inf     % Both main trees are connected
                    this.path = GetPath(q1_joint_p, q2_joint_p, TN_main);
                    this.T_alg = toc(this.T_alg);
                    disp(['Path is found in ', num2str(this.T_alg), ' [s].']);
                    break;
                elseif this.N_nodes >= this.N_max
                    this.T_alg = toc(this.T_alg);
                    disp('Path is not found.');
                    break;
                end            
            end
        end
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    function cost = GetCost(~, q1, q2)
        global robot;
        cost = norm(q1-q2);
%         cost = pdist2(q1', q2', 'seuclidean', 1./sqrt(robot.weights));
    end
    
    
    function q_rand = Get_q_rand(~)        
        global robot tree;        
        if length(tree.nodes) > 2
            N_nodes = zeros(1,length(tree.nodes));
            for i = 1:length(tree.nodes)
                N_nodes(i) = size(tree.nodes{i},2);
            end            
            [N_main, TN] = min(N_nodes(1:2));
            N_extra = sum(N_nodes(3:end));
            if N_extra > N_main
                q_rand = normrnd(tree.nodes{TN}(:,1), (robot.range(:,2)-robot.range(:,1))*N_main/(6*N_extra));
                q_rand(q_rand < -pi) = -pi;
                q_rand(q_rand > pi) = pi;
                return;
            end
        end
        q_rand = (robot.range(:,2)-robot.range(:,1)).*rand(robot.N_DOF,1) + robot.range(:,1);  % Dodavanje nekog random cvora u C-space
    end
    
    
    function [reached, q_new] = ConnectNodes(this, TN, q_p, q_near)
        % Generate spine from q (from tree TN and pointer q_p) to q_near
        
        global tree;
        q = tree.nodes{TN}(:,q_p);
        d_c = tree.distances{TN}(q_p);
        planes = tree.planes{TN}{q_p};
        collision = false;
        reached = false;
        q_new = q;       
             
        while ~collision && ~reached
            % If the distance-to-obstacles is greater/less than d_crit
            if d_c > this.d_crit
                [q_new, reached] = this.GenerateSpine(q_new, q_near, d_c);     % Generating a generalized spine
                d_c = this.Update_d_c(q_new, planes);
            else
                [q_new, reached, collision] = this.GenerateEdge(q_new, q_near);     % Generating a spine according to RRT-paradigm
            end
        end
%         plot(q(1),q(2),'r.');   
%         plot([q(1),q_new(1)],[q(2),q_new(2)],'r');
    end
        
    
    function q_p = OptimizeEdge(this, TN, q_p, TN0, q_parent_p)
        % q (from tree TN and pointer q_p) is optimally connected to tree TN0
        % q_parent_p is a pointer to the node to which q is initially connected
        
        global tree;
        q = tree.nodes{TN}(:,q_p);
        q_opt_p = q_parent_p;  % Pointer to the optimal node
        
        % Finding the optimal edge to the predecessors of q_parent until the collision occurs
        while true
            q_parent_p = tree.pointers{TN0}{q_parent_p}(1); 
            if q_parent_p > 0
                [reached, ~] = this.ConnectNodes(TN, q_p, tree.nodes{TN0}(:,q_parent_p));
                if reached
                    q_opt_p = q_parent_p;                             
                else
                    break;
                end
            else
                break;
            end
        end
        
        if q_parent_p > 0
            change = false;
            q1 = tree.nodes{TN0}(:,q_opt_p);      % It is surely collision-free
            q2 = tree.nodes{TN0}(:,q_parent_p);   % Needs to be collision-checked
            D = norm(q1-q2);
            for ii = 1:floor(log2(10*D))
                q_opt = (q1+q2)/2;
                [reached, ~] = this.ConnectNodes(TN, q_p, q_opt);            
                if reached
                    q1 = q_opt;
                    change = true;
                else
                    q2 = q_opt;
                end
            end
            if change
                q_opt_mod = q1;     % q_opt modified
                q_opt_mod_p = size(tree.nodes{TN0},2)+1;
                tree.nodes{TN0}(:,q_opt_mod_p) = q_opt_mod;
                tree.pointers{TN0}{q_opt_mod_p} = [q_parent_p, q_opt_p];
                ind = find(tree.pointers{TN0}{q_parent_p} == q_opt_p);
                tree.pointers{TN0}{q_parent_p}(ind) = q_opt_mod_p; %#ok<FNDSB>
                tree.pointers{TN0}{q_opt_p}(1) = q_opt_mod_p;
                tree.distances{TN0}(q_opt_mod_p) = NaN;
                tree.planes{TN0}{q_opt_mod_p} = NaN;
                tree.costs{TN0}(q_opt_mod_p) = tree.costs{TN0}(q_parent_p) + this.GetCost(q_opt_mod, tree.nodes{TN0}(:,q_parent_p));
                q_opt_p = q_opt_mod_p;
            end
        end
        
        q_opt = tree.nodes{TN0}(:,q_opt_p);
        cost = tree.costs{TN0}(q_opt_p) + this.GetCost(q, q_opt);
        q_p = UpgradeTree(TN0, q_opt_p, q, tree.distances{TN}(q_p), tree.planes{TN}{q_p}, cost);        
    end
    
    
    function ConnectTrees(this, TN, q_joint_p, TN0, q0_joint_p) 
        % TN - an extra tree
        % TN0 - main tree
        % q_joint_p - Pointer to the node that connects an extra tree with the main tree
        % q0_joint_p - Pointer to the node that connects the main tree with an extra tree
        
        global tree;
        q_considered_p = 0;
        while true
            ConsiderChildren(q_joint_p, q0_joint_p, q_considered_p);
            q_parent_p = tree.pointers{TN}{q_joint_p}(1);
            if q_parent_p == 0
                break;
            end
            q0_joint_p = this.OptimizeEdge(TN, q_parent_p, TN0, q0_joint_p);
            q_considered_p = q_joint_p;
            q_joint_p = q_parent_p;
        end
        
        function ConsiderChildren(q_p, q_new_p, q_considered_p)            
            children_p = GetChildren(TN, q_p, q_considered_p);
            for i = 1:length(children_p)
                q_new_p2 = this.OptimizeEdge(TN, children_p(i), TN0, q_new_p);
                if ~isempty(tree.pointers{TN}{children_p(i)}(2:end))  % Has children
                    ConsiderChildren(children_p(i), q_new_p2, 0);
                end
            end
        end
        
        function children_p = GetChildren(TN, q_p, q_considered_p)
            no_of_children = length(tree.pointers{TN}{q_p})-1;
            if no_of_children > 0  % If children exists
                children_p =  tree.pointers{TN}{q_p}(2:no_of_children+1);
                children_p(children_p == q_considered_p) = [];  % Node that was considered before is not treated as a child   
            else
                children_p = [];
            end
        end
    end
    
    
    function DeleteTree(~, TN)
        global tree;
        tree.nodes(TN) = [];
        tree.pointers(TN) = [];
        tree.distances(TN) = [];
        tree.planes(TN) = [];
        tree.costs(TN) = [];
    end
    
    
    function Draw(this)
        global tree graphics;
        
        for i = 1:length(graphics)
            delete(graphics{i});
        end
        
        k = 1;
        for TN = 1:length(tree.nodes)
            if TN == 1
                color = 'blue';
            elseif TN == 2
                color = 'red';
            else
                color = 'yellow';
            end
            for i = 1:size(tree.nodes{TN},2)
                x = tree.nodes{TN}(:,i);
                for j = 2:length(tree.pointers{TN}{i})
                    y = tree.nodes{TN}(:,tree.pointers{TN}{i}(j));
                    graphics{k} = plot([x(1),y(1)],[x(2),y(2)],'Color',color); hold on;
                    k = k+1;
                end
            end
        end
        drawnow;
        
        if this.cost_opt < inf
            for i = 1:size(this.path,2)-1
                graphics{k} = line([this.path(1,i), this.path(1,i+1)],[this.path(2,i), this.path(2,i+1)],...
                    'Color',[0.7,0.7,0.7],'LineWidth',4); hold on; 
                k = k+1;
            end
            drawnow;
        end
    end
end
end