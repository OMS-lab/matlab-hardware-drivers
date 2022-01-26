classdef arduino_stepper < handle
    %

    properties (Access=public)
        softlim = [0 2000];
        abs_position = 0;
        steps_per_mm = 3.8;
    end
    
    properties %(Access=protected)

        %arduino connection
        a;
        power_pin = 'D5';
        direction_pin = 'D4';
        step_pin = 'D3';
        
        % (depends on controller)
        steps_per_rev = 20;

        zero = 0;
        
        locations = [0,45,-45];

    end
    
    properties (Dependent)
        position
    end
    
    methods
        function connect(obj)
            obj.a = arduino('COM10');
            
            %move to position 1
            obj.position = 1;
        end
        
        function power_on(obj)
            obj.a.writeDigitalPin(obj.power_pin,1); 
        end
            
        function power_off(obj)
            obj.a.writeDigitalPin(obj.power_pin,0); 
        end
        
        function move(obj,distance)
            %set direction
            if distance < 0
                direction = false;
                distance = abs(distance);
            else
                direction = true;
            end
            obj.a.writeDigitalPin(obj.direction_pin,direction);            
            
            %turn on the power
            obj.power_on();
            
            %detemrine soft limits
            temp_dir = (-1)^(direction+1); %+ve (1) is clockwise, -ve (0) is anticlockwise
            temp_pos = obj.abs_position + temp_dir*distance;
            
            %If outside soft limits, redefine distance and display warning
            if temp_pos < obj.softlim(1) 
                disp('Set position lies outside of soft limit, setting to min soft limit');
                temp_pos = obj.softlim(1);
                distance = (temp_pos - obj.abs_position)/temp_dir;
            elseif temp_pos > obj.softlim(2)
                disp('Set position lies outside of soft limit, setting to max soft limit');
                temp_pos = obj.softlim(2);     
                distance = (temp_pos - obj.abs_position)/temp_dir;
            end

            
            %calculate pause time from velocity
            steps = obj.steps_per_mm*distance;
%             time = 0.0001 %distance/(obj.velocity*steps)
            
            %move distance in mm
            for i = 1:steps
               obj.a.writeDigitalPin(obj.step_pin,1);
               %pause(time/2);
               obj.a.writeDigitalPin(obj.step_pin,0);
               %pause(time/2);
            end 
            
            obj.abs_position = obj.abs_position + temp_dir*distance;
            
            %turn off the power
            obj.power_off();
        end
        
        function out = get.position(obj)
            arguments
               obj
            end
            
            o = obj.abs_position;
            index = find(obj.locations==o);
            out = index;
        end        
       
        
        function set.position(obj,A)
            arguments
               obj
               A (1,1) 
            end
            
            %find absolute position of location
            p = obj.locations(A);
            
            %calculate distance to travel
            d = p - obj.abs_position;
            
            %move to new position
            obj.move(d);
            
        end
                
    end
    
    methods (Access=protected)


    end
end