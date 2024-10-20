max_vessel = property.slider("Max Vessel Count", 0, 256, 1, 128)
max_aircraft = property.slider("Max Aircraft Count", 0, 256, 1, 64)
starting_percentage = property.slider("Start AI Percentage", 0, 100, 1, 100)
respawn_frequency = property.slider("Respawn Frequency (minutes)", 0, 60, 1, 5)

g_savedata = { vehicles = {}, airfields = {} }

built_locations = {}
unique_locations = {}

local render_debug = false

local debug_mode = false

local g_debug_vehicle_id = "0"

aircraft_start_height = 500
cruise_height = 300
update_all = true
tick_counter = 0

aircraft_count = 0
vessel_count = 0

holding_pattern = {
    {x=500, z=500},
    {x=500, z=-500},
    {x=-500, z=-500},
    {x=-500, z=500}
}

function build_airfields()

    g_savedata.airfields = server.getZones("type=helipad")

    for airfield_index, airfield in pairs(g_savedata.airfields) do
        airfield.queue = {}
        airfield.landing_timer = 0
    end

end

function onCreate(is_world_create)

    for i in iterPlaylists() do
        for j in iterLocations(i) do
            build_locations(i, j)
        end
    end

    if is_world_create then

        build_airfields()

        for i = 1, math.floor(max_aircraft*starting_percentage/100) do
            spawnAircraft()
        end
        for i = 1, math.floor(max_vessel*starting_percentage/100) do
            spawnVessel()
        end

        for i = 1, #unique_locations do

            local location = unique_locations[i]

            local random_transform = matrix.translation(math.random(location.objects.vehicle.bounds.x_min, location.objects.vehicle.bounds.x_max), 0, math.random(location.objects.vehicle.bounds.z_min, location.objects.vehicle.bounds.z_max))

            local spawn_transform, is_success = server.getOceanTransform(random_transform, 1000, 10000)
            if location.ai_type == "heli" or location.ai_type == "plane" then
                spawn_transform = matrix.multiply(spawn_transform, matrix.translation(math.random(-500, 500), aircraft_start_height, math.random(-500, 500)))
            else
                spawn_transform = matrix.multiply(spawn_transform, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))
            end
            if is_success then
                local all_mission_objects = {}
                local spawned_objects = {
                    vehicle = spawnObject(spawn_transform, location.playlist_index, location.location_index, location.objects.vehicle, 0, nil, all_mission_objects),
                    survivors = spawnObjects(spawn_transform, location.playlist_index,location.location_index, location.objects.survivors, all_mission_objects),
                    objects = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.objects, all_mission_objects),
                    zones = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.zones, all_mission_objects)
                }

                g_savedata.vehicles[spawned_objects.vehicle.id] = {survivors = spawned_objects.survivors, destination = { x = 0, z = 0 },  path = {}, map_id = server.getMapID(), state = { s = "pseudo", timer = math.fmod(spawned_objects.vehicle.id, 300) }, bounds = location.objects.vehicle.bounds, size = spawned_objects.vehicle.size, current_damage = 0, despawn_timer = 0, ai_type = spawned_objects.vehicle.ai_type }
            end
        end
    else
        for vehicle_id, vehicle_object in pairs(g_savedata.vehicles) do

            if not isAircraft(vehicle_object.ai_type) then
                if vehicle_object.path == nil then
                    if createDestination(vehicle_id) then
                        vehicle_object.path = createPath(vehicle_id)
                    end
                end

                if server.getVehicleSimulating(vehicle_id) then
                    vehicle_object.state.s = "pathing"
                else
                    vehicle_object.state.s = "pseudo"
                end
            else
                if vehicle_object.state.s == "approach" or vehicle_object.state.s == "landing" or vehicle_object.state.s == "land_wait" or vehicle_object.state.s == "takeoff" then

                    vehicle_object.state.s = "waiting"

                    local vehicle_pos = server.getVehiclePos(vehicle_id)
                    local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_pos)
                    local new_pos = matrix.translation(vehicle_x, vehicle_start_height, vehicle_z)
                    local vehicle_data = server.getVehicleData(vehicle_id)
                    local success, new_transform = server.moveGroupSafe(vehicle_data.group_id, new_pos)

                    for npc_index, npc_object in pairs(vehicle_object.survivors) do
                        server.setObjectPos(npc_object.id, new_transform)
                    end
                end
            end
            if vehicle_object.bounds == nil then
                vehicle_object.bounds = { x_min = -40000, z_min = -40000, x_max = 40000, z_max = 140000}
            end
            if vehicle_object.current_damage == nil then vehicle_object.current_damage = 0 end
            if vehicle_object.despawn_timer == nil then vehicle_object.despawn_timer = 0 end
        end

    end
end

function build_locations(playlist_index, location_index)
    local location_data = server.getLocationData(playlist_index, location_index)

    local mission_objects =
    {
        vehicle = nil,
        survivors = {},
        objects = {},
        zones = {},
    }

    local is_valid = false
    local is_unique = false
    local bounds = { x_min = -40000, z_min = -40000, x_max = 40000, z_max = 140000}
    local _ai_type = "default"
    for object_index, object_data in iterObjects(playlist_index, location_index) do

        object_data.index = object_index

        -- investigate tags

        for tag_index, tag_object in pairs(object_data.tags) do
            if tag_object == "type=ai_heli" then
                is_valid = true
                _ai_type = "heli"
            elseif tag_object == "type=ai_plane" then
                is_valid = true
                _ai_type = "plane"
            elseif tag_object == "type=ai_boat" then
                is_valid = true
            elseif tag_object == "unique" then
                is_unique = true
            elseif string.find(tag_object, "x_min=") ~= nil then
                bounds.x_min = tonumber(string.sub(tag_object, 7))
            elseif string.find(tag_object, "z_min=") ~= nil then
                bounds.z_min = tonumber(string.sub(tag_object, 7))
            elseif string.find(tag_object, "x_max=") ~= nil then
                bounds.x_max = tonumber(string.sub(tag_object, 7))
            elseif string.find(tag_object, "z_max=") ~= nil then
                bounds.z_max = tonumber(string.sub(tag_object, 7))
            end
        end

        if object_data.type == "vehicle" then
            if mission_objects.vehicle == nil then
                mission_objects.vehicle = object_data
            end
        elseif object_data.type == "character" then
            table.insert(mission_objects.survivors, object_data)
        elseif object_data.type == "object" then
            table.insert(mission_objects.objects, object_data)
        elseif object_data.type == "zone" then
            table.insert(mission_objects.zones, object_data)
        end
    end

    if is_valid then
        if mission_objects.vehicle ~= nil and #mission_objects.survivors > 0 then

            mission_objects.vehicle.bounds = bounds

            if is_unique then
                table.insert(unique_locations, { playlist_index = playlist_index, location_index = location_index, data = location_data, objects = mission_objects, ai_type=_ai_type} )
            else
                table.insert(built_locations, { playlist_index = playlist_index, location_index = location_index, data = location_data, objects = mission_objects, ai_type=_ai_type} )
            end
        end
    end
end

function onVehicleUnload(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object ~= nil then
        if isAircraft(vehicle_object.ai_type) then
            vehicle_object.state.is_simulating = false
        else
            vehicle_object.state.s = "pseudo"
        end
    end

end

function onVehicleLoad(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object ~= nil then
        if isAircraft(vehicle_object.ai_type) then
            vehicle_object.state.is_simulating = true
        else
            vehicle_object.state.s = "pathing"
        end

        for npc_index, npc in pairs(vehicle_object.survivors) do
            local c = server.getCharacterData(npc.id)
            if c then
                server.setCharacterData(npc.id, c.hp, false, true)
                server.setCharacterSeated(npc.id, vehicle_id, c.name)
            end
        end
        refuel(vehicle_id)
        if isAircraft(vehicle_object.ai_type) then
            server.setAITarget(vehicle_object.survivors[1].id, matrix.identity())
            server.setAIState(vehicle_object.survivors[1].id, 1)
        end
    end
end

function createAircraftPath(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not isAircraft(vehicle_object.ai_type) then
        log("boat trying to create aircraft path "..tostring(vehicle_id))
    end
    local random_number = math.random(1, 30)

    if(#g_savedata.airfields > 0) then
        selected_airfield_index = math.random(1, #g_savedata.airfields)
    end

    vehicle_object.path = {}

    if(#g_savedata.airfields > 0 and vehicle_object.ai_type == "heli" and ((random_number <= 5 and #g_savedata.airfields[selected_airfield_index].queue < 3))) then

        local dest_x, dest_y, dest_z = matrix.position(g_savedata.airfields[selected_airfield_index].transform)
        table.insert(vehicle_object.path, { x = dest_x, y = dest_y, z = dest_z, dest_type = "airfield", airfield_index = selected_airfield_index })

    elseif(random_number <= 14) then

        -- patrol between two points

        local random_transform = matrix.translation(math.random(vehicle_object.bounds.x_min, vehicle_object.bounds.x_max), 0, math.random(vehicle_object.bounds.z_min, vehicle_object.bounds.z_max))
        local destination_pos_1 = matrix.multiply(random_transform, matrix.translation(math.random(-500, 500), cruise_height + (vehicle_id % 10 * 20), math.random(-500, 500)))
        local destination_pos_2 = matrix.multiply(random_transform, matrix.translation(math.random(-3500, 3500), cruise_height + (vehicle_id % 10 * 20), math.random(-3500, 3500)))

        local dest_x, dest_y, dest_z = matrix.position(destination_pos_1)
        table.insert(vehicle_object.path, { x = dest_x, y = cruise_height + (vehicle_id % 10 * 20), z = dest_z, dest_type = "", airfield_index = nil })

        local dest_x, dest_y, dest_z = matrix.position(destination_pos_2)
        table.insert(vehicle_object.path, { x = dest_x, y = cruise_height + (vehicle_id % 10 * 20), z = dest_z, dest_type = "", airfield_index = nil })

        local dest_x, dest_y, dest_z = matrix.position(destination_pos_1)
        table.insert(vehicle_object.path, { x = dest_x, y = cruise_height + (vehicle_id % 10 * 20), z = dest_z, dest_type = "", airfield_index = nil })

        local dest_x, dest_y, dest_z = matrix.position(destination_pos_2)
        table.insert(vehicle_object.path, { x = dest_x, y = cruise_height + (vehicle_id % 10 * 20), z = dest_z, dest_type = "", airfield_index = nil })

        local dest_x, dest_y, dest_z = matrix.position(destination_pos_1)
        table.insert(vehicle_object.path, { x = dest_x, y = cruise_height + (vehicle_id % 10 * 20), z = dest_z, dest_type = "", airfield_index = nil })

    else

        -- go to a random destination

        local random_transform = matrix.translation(math.random(vehicle_object.bounds.x_min, vehicle_object.bounds.x_max), 0, math.random(vehicle_object.bounds.z_min, vehicle_object.bounds.z_max))
        local destination_pos = matrix.multiply(random_transform, matrix.translation(math.random(-500, 500), cruise_height + (vehicle_id % 10 * 20), math.random(-500, 500)))
        local dest_x, dest_y, dest_z = matrix.position(destination_pos)

        table.insert(vehicle_object.path, { x = dest_x, y = cruise_height + (vehicle_id % 10 * 20), z = dest_z, dest_type = "", airfield_index = nil })

    end
end

function createDestination(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]

    local random_transform = matrix.translation(math.random(vehicle_object.bounds.x_min, vehicle_object.bounds.x_max), 0, math.random(vehicle_object.bounds.z_min, vehicle_object.bounds.z_max))
    local target_pos, is_success = server.getOceanTransform(random_transform, 1000, 10000)

    if is_success == false then return false end

    local destination_pos = matrix.multiply(target_pos, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))
    local dest_x, dest_y, dest_z = matrix.position(destination_pos)

    vehicle_object.destination.x = dest_x
    vehicle_object.destination.z = dest_z

    return true
end

function createPath(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]
    local vehicle_pos = server.getVehiclePos(vehicle_id)

    local avoid_tags = "size=null"
    if vehicle_object.size == "large" then
        avoid_tags = "size=null,size=small,size=medium"
    end
    if vehicle_object.size == "medium" then
        avoid_tags = "size=null,size=small"
    end

    local path_list = server.pathfind(vehicle_pos, (matrix.translation(vehicle_object.destination.x, 50, vehicle_object.destination.z)), "ocean_path", avoid_tags)
    for path_index, path in pairs(path_list) do
        path.ui_id = server.getMapID()
    end

    if render_debug then
        if tostring(vehicle_id) == g_debug_vehicle_id or g_debug_vehicle_id == tostring(0) then
            if(#vehicle_object.path >= 1) then
                server.removeMapLine(0, vehicle_object.map_id)
                server.addMapLine(0, vehicle_object.map_id, vehicle_pos, matrix.translation(vehicle_object.path[1].x, vehicle_object.path[1].y, vehicle_object.path[1].z), 0.5, 0, 0, 255, 255)

                for i = 1, #vehicle_object.path - 1 do
                    local waypoint = vehicle_object.path[i]
                    local waypoint_next = vehicle_object.path[i + 1]

                    local waypoint_pos = matrix.translation(waypoint.x, waypoint.y, waypoint.z)
                    local waypoint_pos_next = matrix.translation(waypoint_next.x, waypoint_next.y, waypoint_next.z)

                    server.removeMapLine(0, waypoint.ui_id)
                    server.addMapLine(0, waypoint.ui_id, waypoint_pos, waypoint_pos_next, 0.5, 0, 0, 255, 255)
                end
            end
        end
    end

    return path_list
end

function onTick(tick_time)
    --tick airfields
    for airfield_index, airfield in pairs(g_savedata.airfields) do

        if(#airfield.queue > 0) then
            if(airfield.queue[1].state.s == "holding") then
                if airfield.queue[1].state.is_simulating then
                    airfield.queue[1].state.s = "approach"
                    airfield.landing_timer = 0
                else
                    airfield.queue[1].state.s = "waiting"
                end
            elseif(airfield.queue[1].state.s == "landing") then
                airfield.landing_timer = airfield.landing_timer + 1
            end
        end
    end
    aircraft_count = 0
    vessel_count = 0
    for vehicle_id, vehicle_object in pairs(g_savedata.vehicles) do
        local _,vehicle_success = server.getVehicleData(vehicle_id)
        if not vehicle_success then
            cleanupVehicle(vehicle_id)
        end
        if vehicle_object ~= nil and vehicle_success then
            vehicle_object.state.timer = vehicle_object.state.timer + 1

            if isAircraft(vehicle_object.ai_type) then
                aircraft_count = aircraft_count + 1
            elseif vehicle_object.ai_type == "default" then
                vessel_count = vessel_count + 1
            end

            if not isAircraft(vehicle_object.ai_type) then
                if vehicle_object.state.s == "pathing" then

                    if #vehicle_object.path > 0 then

                        if vehicle_object.state.timer >= 300 then

                            vehicle_object.state.timer = 0

                            k1 = true

                            local vehicle_pos = server.getVehiclePos(vehicle_id)
                            local distance = calculate_distance_to_next_waypoint(vehicle_object.path[1], vehicle_pos)
                            local player_distance = 9999
                            if vehicle_object.ai_type == "hospital" then
                                local players = server.getPlayers()
                                local random_player = players[math.random(1, #players)]
                                local random_player_transform = server.getPlayerPos(random_player.id)
                                player_distance = matrix.distance(random_player_transform, vehicle_pos)
                            end

                            if (vehicle_object.ai_type == "hospital" and player_distance < 50) then
                                server.setAIState(vehicle_object.survivors[1].id, 0)
                            else
                                server.setAITarget(vehicle_object.survivors[1].id, (matrix.translation(vehicle_object.path[1].x, 0, vehicle_object.path[1].z)))
                                server.setAIState(vehicle_object.survivors[1].id, 1)
                            end
                            refuel(vehicle_id)

                            if distance < 100 then
                                table.remove(vehicle_object.path, 1)
                            end
                        end

                    else
                        vehicle_object.state.s = "waiting"
                        server.setAIState(vehicle_object.survivors[1].id, 0)
                    end

                elseif vehicle_object.state.s == "waiting" then

                    local wait_time = 3600
                    if vehicle_object.ai_type == "hospital" then wait_time = 3600 * 30 end

                    if vehicle_object.state.timer >= wait_time then
                        vehicle_object.state.timer = 0

                        if render_debug then
                            for i = 1, #vehicle_object.path - 1 do
                                server.removeMapLine(0, vehicle_object.path[i].ui_id)
                            end
                        end

                        if createDestination(vehicle_id) then
                            vehicle_object.path = createPath(vehicle_id)

                            if server.getVehicleSimulating(vehicle_id) then
                                vehicle_object.state.s = "pathing"
                            else
                                vehicle_object.state.s = "pseudo"
                            end

                            refuel(vehicle_id)
                        end
                    end

                elseif vehicle_object.state.s == "pseudo" then

                    if vehicle_object.state.timer >= 900 then

                        vehicle_object.state.timer = 0

                        if #vehicle_object.path > 0 then
                            local vehicle_transform = server.getVehiclePos(vehicle_id)
                            local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_transform)

                            local speed = 60
                            local movement_x = vehicle_object.path[1].x - vehicle_x
                            local movement_z = vehicle_object.path[1].z - vehicle_z

                            local length_xz = math.sqrt((movement_x * movement_x) + (movement_z * movement_z))

                            movement_x = movement_x * speed / length_xz
                            movement_z = movement_z * speed / length_xz

                            local rotation_matrix = matrix.rotationToFaceXZ(movement_x, movement_z)
                            local new_pos = matrix.multiply(matrix.translation(vehicle_x + movement_x, 0, vehicle_z + movement_z), rotation_matrix)

                            if server.getVehicleLocal(vehicle_id) == false then
                                local vehicle_data = server.getVehicleData(vehicle_id)
                                local success, new_transform = server.moveGroupSafe(vehicle_data.group_id, new_pos)
                                for npc_index, npc_object in pairs(vehicle_object.survivors) do
                                    server.setObjectPos(npc_object.id, new_transform)
                                end
                            end

                            local distance = calculate_distance_to_next_waypoint(vehicle_object.path[1], vehicle_transform)
                            if distance < 100 then
                                table.remove(vehicle_object.path, 1)
                            end
                        else
                            vehicle_object.state.s = "waiting"
                            server.setAIState(vehicle_object.survivors[1].id, 0)
                        end
                    end
                end

                if render_debug then
                    if tostring(vehicle_id) == g_debug_vehicle_id or g_debug_vehicle_id == tostring(0) then

                        local vehicle_pos = server.getVehiclePos(vehicle_id)
                        local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_pos)

                        local debug_data = vehicle_object.state.s .. " : " .. vehicle_object.state.timer .. "\n"

                        if vehicle_object.size then debug_data = debug_data .. "Size: " .. vehicle_object.size .. "\n" end
                        debug_data = debug_data .. "Pos: " .. math.floor(vehicle_x) .. "\n".. math.floor(vehicle_y) .. "\n".. math.floor(vehicle_z) .. "\n"

                        server.removeMapObject(0, vehicle_object.map_id)
                        server.addMapObject(0, vehicle_object.map_id, 1, 17, v_x, v_z, 0, 0, vehicle_id, 0, "AI Boat" .. vehicle_id, 1, debug_data)
                    end
                end

                local vehicle_hp = 4000
                explosion_size = 0.6
                if vehicle_object.size == "large" then
                    vehicle_hp = 100000
                    explosion_size = 1.5
                end
                if vehicle_object.size == "medium" then
                    vehicle_hp = 10000
                    explosion_size = 1.0
                end
                if  vehicle_object.current_damage > vehicle_hp then
                    vehicle_object.despawn_timer = vehicle_object.despawn_timer + 1
                end

                if vehicle_object.state.timer == 0 or (vehicle_object.despawn_timer > 60 * 60 * 2) then
                    local vehicle_pos = server.getVehiclePos(vehicle_id)
                    if vehicle_pos[14] < -22 or vehicle_object.despawn_timer > 2 * 1 * 1 then
                        server.despawnVehicle(vehicle_id, true) --clean up code moved further down the line for instantly destroyed vehicle
                    end
                end

            elseif vehicle_object.ai_type == "heli" or vehicle_object.ai_type == "plane" then
                local update_behaviour = false
                local ai_target = nil
                local ai_state = 1
                local ai_speed_pseudo = 150

                --tick timers
                vehicle_object.state.timer = vehicle_object.state.timer + 1

                --tick state
                if vehicle_object.state.s == "pathing" then

                    if(#vehicle_object.path < 1) then
                        vehicle_object.state.s = "waiting"
                    else

                        if vehicle_object.state.is_simulating then
                            if vehicle_object.state.timer >= 300 then
                                vehicle_object.state.timer = 0
                                update_behaviour = true
                            end
                        else
                            if vehicle_object.state.timer >= 900 then
                                vehicle_object.state.timer = 0
                                update_behaviour = true
                            end
                        end

                        if vehicle_object.ai_type == "plane" then
                            ai_speed_pseudo = 750
                        else
                            ai_speed_pseudo = 400
                        end

                        if render_debug then
                            ai_target = matrix.translation(vehicle_object.path[1].x, cruise_height + (vehicle_id % 10 * 20), vehicle_object.path[1].z)
                        end

                        if update_all or update_behaviour then
                            ai_state = 1
                            ai_target = matrix.translation(vehicle_object.path[1].x, cruise_height + (vehicle_id % 10 * 20), vehicle_object.path[1].z)

                            local vehicle_pos = server.getVehiclePos(vehicle_id)
                            local distance = matrix.distance(ai_target, vehicle_pos)

                            if distance < 500 then
                                if vehicle_object.state.is_simulating == false then
                                    update_behaviour = false -- prevent overshooting
                                end
                                if(vehicle_object.path[1].dest_type == "airfield") then
                                    vehicle_object.state.s = "holding"
                                    vehicle_object.holding_index = 1
                                    table.insert(g_savedata.airfields[vehicle_object.path[1].airfield_index].queue, vehicle_object)
                                else
                                    table.remove(vehicle_object.path, 1)
                                    vehicle_object.state.s = "waiting"
                                end
                            end

                            refuel(vehicle_id)
                        end
                    end

                elseif vehicle_object.state.s == "waiting" then

                    vehicle_object.state.timer = 0

                    createAircraftPath(vehicle_id)

                    vehicle_object.state.s = "pathing"
                    refuel(vehicle_id)

                elseif vehicle_object.state.s == "holding" then

                    ai_speed_pseudo = 50
                    if render_debug then
                        ai_target = matrix.translation(vehicle_object.path[1].x + holding_pattern[vehicle_object.holding_index].x, cruise_height + (vehicle_id % 10 * 20), vehicle_object.path[1].z + holding_pattern[vehicle_object.holding_index].z)
                    end

                    if vehicle_object.state.timer >= 600 then
                        vehicle_object.state.timer = 0
                        update_behaviour = true
                    end
                    if update_all or update_behaviour then
                        ai_state = 1
                        ai_target = matrix.translation(vehicle_object.path[1].x + holding_pattern[vehicle_object.holding_index].x, cruise_height + (vehicle_id % 10 * 20), vehicle_object.path[1].z + holding_pattern[vehicle_object.holding_index].z)

                        local vehicle_pos = server.getVehiclePos(vehicle_id)
                        local distance = matrix.distance(ai_target, vehicle_pos)

                        if distance < 100 then
                            vehicle_object.holding_index = 1 + ((vehicle_object.holding_index) % 4);
                        end
                    end

                elseif vehicle_object.state.s == "approach" then

                    ai_speed_pseudo = 20
                    if render_debug then
                        ai_target = matrix.multiply(g_savedata.airfields[vehicle_object.path[1].airfield_index].transform,  matrix.translation(0, 300, 100))
                    end

                    if vehicle_object.state.timer >= 300 then
                        vehicle_object.state.timer = 0
                        update_behaviour = true
                    end
                    if update_all or update_behaviour then
                        ai_state = 1
                        ai_target = matrix.multiply(g_savedata.airfields[vehicle_object.path[1].airfield_index].transform,  matrix.translation(0, 300, 100))

                        local vehicle_pos = server.getVehiclePos(vehicle_id)
                        local distance = matrix.distance(ai_target, vehicle_pos)
                        if distance < 50 then
                            vehicle_object.state.s = "landing"
                            vehicle_object.state.timer = 0
                        end

                        refuel(vehicle_id)
                    end

                elseif vehicle_object.state.s == "landing" then

                    ai_speed_pseudo = 5
                    if render_debug then
                        ai_target = matrix.translation(vehicle_object.path[1].x, vehicle_object.path[1].y - 5, vehicle_object.path[1].z)
                    end

                    if vehicle_object.state.timer >= 300 then
                        update_behaviour = true
                    end
                    if update_all or update_behaviour then
                        ai_state = 2
                        ai_target = matrix.translation(vehicle_object.path[1].x, vehicle_object.path[1].y - 5, vehicle_object.path[1].z)

                        -- 10 min max wait time for landing
                        if g_savedata.airfields[vehicle_object.path[1].airfield_index].landing_timer >= 36000 then
                            vehicle_object.state.s = "takeoff"
                        end

                        local vehicle_pos = server.getVehiclePos(vehicle_id)
                        local distance = matrix.distance(ai_target, vehicle_pos)
                        if distance < 10 then
                            if vehicle_object.state.timer >= 900 then
                                vehicle_object.state.s = "land_wait"
                                ai_state = 0
                                vehicle_object.state.timer = 0
                            end
                        else
                            vehicle_object.state.timer = 0
                        end

                        refuel(vehicle_id)
                    end

                elseif vehicle_object.state.s == "land_wait" then

                    ai_speed_pseudo = 0

                    if vehicle_object.state.timer >= 6000 then
                        vehicle_object.state.timer = 0
                        vehicle_object.state.s = "takeoff"
                        refuel(vehicle_id)
                    end

                elseif vehicle_object.state.s == "takeoff" then

                    ai_speed_pseudo = 5
                    if render_debug then
                        ai_target = matrix.multiply(g_savedata.airfields[vehicle_object.path[1].airfield_index].transform, matrix.translation(0, 300, -100))
                    end

                    if vehicle_object.state.timer >= 300 then
                        vehicle_object.state.timer = 0
                        update_behaviour = true
                    end
                    if update_all or update_behaviour then
                        ai_state = 2
                        ai_target = matrix.multiply(g_savedata.airfields[vehicle_object.path[1].airfield_index].transform, matrix.translation(0, 300, -100))

                        local vehicle_pos = server.getVehiclePos(vehicle_id)
                        local distance = matrix.distance(ai_target, vehicle_pos)
                        if distance < 50 then
                            table.remove(g_savedata.airfields[vehicle_object.path[1].airfield_index].queue, 1)
                            vehicle_object.state.s = "waiting"
                        end

                        refuel(vehicle_id)
                    end

                end

                --set ai behaviour
                if (update_all or update_behaviour) and (ai_target ~= nil) then
                    if vehicle_object.state.is_simulating then
                        server.setAITarget(vehicle_object.survivors[1].id, ai_target)
                        server.setAIState(vehicle_object.survivors[1].id, ai_state)
                    else
                        local ts_x, ts_y, ts_z = matrix.position(ai_target)
                        local vehicle_pos = server.getVehiclePos(vehicle_id)
                        local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_pos)
                        local movement_x = ts_x - vehicle_x
                        local movement_y = ts_y - vehicle_y
                        local movement_z = ts_z - vehicle_z
                        local length_xz = math.sqrt((movement_x * movement_x) + (movement_z * movement_z))
                        movement_x = movement_x * ai_speed_pseudo / length_xz
                        movement_y = math.min(ai_speed_pseudo, math.max(movement_y, -ai_speed_pseudo))
                        movement_z = movement_z * ai_speed_pseudo / length_xz

                        local rotation_matrix = matrix.rotationToFaceXZ(movement_x, movement_z)
                        local new_pos = matrix.multiply(matrix.translation(vehicle_x + movement_x, vehicle_y + movement_y, vehicle_z + movement_z), rotation_matrix)

                        if server.getVehicleLocal(vehicle_id) == false then
                            local vehicle_data = server.getVehicleData(vehicle_id)
                            local success, new_transform = server.moveGroupSafe(vehicle_data.group_id, new_pos)

                            for npc_index, npc_object in pairs(vehicle_object.survivors) do
                                server.setObjectPos(npc_object.id, new_transform)
                            end
                        end
                    end
                end

                if render_debug then
                    local vehicle_pos = server.getVehiclePos(vehicle_id)
                    local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_pos)

                    local debug_data = vehicle_object.state.s .. " : " .. vehicle_object.state.timer .. "\n"

                    debug_data = debug_data .. "Pos: " .. math.floor(vehicle_x) .. "\n".. math.floor(vehicle_y) .. "\n".. math.floor(vehicle_z) .. "\n"
                    if ai_target then
                        local ts_x, ts_y, ts_z = matrix.position(ai_target)
                        debug_data = debug_data .. "Dest: " .. math.floor(ts_x) .. "\n".. math.floor(ts_y) .. "\n".. math.floor(ts_z) .. "\n"
                    end

                    if(#vehicle_object.path > 0) then
                        debug_data = debug_data .. "Dest type: " .. vehicle_object.path[1].dest_type .. "\n"
                    end

                    server.removeMapObject(0 ,vehicle_object.map_id)
                    server.addMapObject(0, vehicle_object.map_id, 1, vehicle_object.ai_type == "heli" and 15 or 13, v_x, v_z, 0, 0, vehicle_id, 0, "AI " .. vehicle_object.ai_type .. " " .. vehicle_id, 1, debug_data)
                end

                --debug render
                if render_debug and vehicle_object.state.is_simulating then
                    local vehicle_pos = server.getVehiclePos(vehicle_id)
                    local v_x, v_y, v_z = matrix.position(vehicle_pos)
                    local target_data = server.getAITarget(vehicle_object.survivors[1].id)
                    local popup_text = "state: ".. vehicle_object.state.s
                    if(#vehicle_object.path >= 1) then
                        popup_text = popup_text .. "\ndest_server: " .. math.floor(target_data.x) .. " " .. math.floor(target_data.y) .. " " .. math.floor(target_data.z)
                    end
                    server.setPopup(0, vehicle_object.ui_id, "test", true, popup_text, v_x, v_y + 40, v_z, 0)
                end

                if  vehicle_object.current_damage > 800 then
                    vehicle_object.despawn_timer = vehicle_object.despawn_timer + 1
                end

                if (update_all or update_behaviour) or (vehicle_object.despawn_timer > 60 * 60 * 2) then
                    local vehicle_pos = server.getVehiclePos(vehicle_id)
                    if vehicle_pos[14] < -20 or  vehicle_object.despawn_timer > 60 * 60 * 2 then
                        server.despawnVehicle(vehicle_id, true) --clean up code moved further down the line for instantly destroyed vehicle
                    end
                end

                update_all = false
            end
        end
    end

    if isTickID(0, respawn_frequency*60*60) then
        spawnVessel()
    end
    if isTickID(1, respawn_frequency*60*60) then
        spawnAircraft()
    end
    tick_counter = tick_counter + 1
end

function onVehicleDamaged(vehicle_id, amount, x, y, z, body_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object ~= nil then
        vehicle_object.current_damage = vehicle_object.current_damage + amount
    end
end

function onVehicleDespawn(vehicle_id, peer_id)
    if g_savedata.vehicles[vehicle_id] == nil then
        return
    end
    cleanupVehicle(vehicle_id)
end

function cleanupVehicle(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object == nil then
        return
    end
    g_savedata.vehicles[vehicle_id] = nil

    local vehicle_pos = server.getVehiclePos(vehicle_id)
    server.spawnExplosion(vehicle_pos, explosion_size)

    server.removeMapObject(-1, vehicle_object.map_id)
    server.removeMapLine(-1, vehicle_object.map_id)
    for _, waypoint in pairs(vehicle_object.path) do
        server.removeMapLine(-1, waypoint.ui_id)
    end
    for _, survivor in pairs(vehicle_object.survivors) do
        server.despawnObject(survivor.id, true)
    end
end

function summonHospitalShip(x, z)

    local id=nil
    local object=nil
    local distsq=nil

    for vehicle_id, vehicle_object in pairs(g_savedata.vehicles) do
        if vehicle_object.ai_type == "hospital" then
            local vehicle_transform = server.getVehiclePos(vehicle_id)
            local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_transform)

            local vector_x = vehicle_x - x
            local vector_z = vehicle_z - z

            local this_distsq = (vector_x * vector_x) + (vector_z * vector_z)

            if distsq == nil or this_distsq < distsq then
                object = vehicle_object
                id = vehicle_id
                distsq = this_distsq
            end
        end
    end

    if object ~= nil then
        local random_transform = matrix.translation(x, 0, z)
        local target_pos, success = server.getOceanTransform(random_transform, 1000, 2000)

        if success then
            local destination_pos = matrix.multiply(target_pos, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))
            local dest_x, dest_y, dest_z = matrix.position(destination_pos)

            if render_debug then
                for i = 1, #object.path - 1 do
                    server.removeMapLine(0, object.path[i].ui_id)
                end
            end

            object.destination.x = dest_x
            object.destination.z = dest_z
            object.path = createPath(id)

            if server.getVehicleSimulating(id) then
                object.state.s = "pathing"
            else
                object.state.s = "pseudo"
            end
        end

        refuel(id)
    end
end

function onCustomCommand(full_message, peer_id, is_admin, is_auth, command, arg1, arg2, arg3, arg4)

    if peer_id == -1 then
        if command == "?ai_summon_hospital_ship" then
            summonHospitalShip(arg1, arg2)
        end
    else
        if command == "?ai_debug" and is_admin then
            render_debug = not render_debug

            if arg1 ~= nil then
                g_debug_vehicle_id = arg1
            else
                g_debug_vehicle_id = tostring(0)
            end

            for vehicle_id, vehicle_object in pairs(g_savedata.vehicles) do
                server.removeMapObject(0, vehicle_object.map_id)
                server.removeMapLine(0, vehicle_object.map_id)
                for i = 1, #vehicle_object.path - 1 do
                    server.removeMapLine(0, vehicle_object.path[i].ui_id)
                end

                if render_debug then
                    if tostring(vehicle_id) == g_debug_vehicle_id or g_debug_vehicle_id == tostring(0) then
                        local vehicle_pos = server.getVehiclePos(vehicle_id)
                        if(#vehicle_object.path >= 1) then
                            server.removeMapLine(0, vehicle_object.map_id)
                            server.addMapLine(0, vehicle_object.map_id, vehicle_pos, matrix.translation(vehicle_object.path[1].x, vehicle_object.path[1].y, vehicle_object.path[1].z), 0.5, 0, 0, 255, 255)

                            for i = 1, #vehicle_object.path - 1 do
                                local waypoint = vehicle_object.path[i]
                                local waypoint_next = vehicle_object.path[i + 1]

                                local waypoint_pos = matrix.translation(waypoint.x, waypoint.y, waypoint.z)
                                local waypoint_pos_next = matrix.translation(waypoint_next.x, waypoint_next.y, waypoint_next.z)

                                server.removeMapLine(0, waypoint.ui_id)
                                server.addMapLine(0, waypoint.ui_id, waypoint_pos, waypoint_pos_next, 0.5, 0, 0, 255, 255)
                            end
                        end
                    end
                end
            end
        end
    end
end

function refuel(vehicle_id)
    server.setVehicleTank(vehicle_id, "jet1", 999, 2)
    server.setVehicleTank(vehicle_id, "jet2", 999, 2)
    server.setVehicleTank(vehicle_id, "diesel1", 999, 1)
    server.setVehicleTank(vehicle_id, "diesel2", 999, 1)
    server.setVehicleBattery(vehicle_id, "battery1", 1)
    server.setVehicleBattery(vehicle_id, "battery2", 1)
end

function calculate_distance_to_next_waypoint(path_pos, vehicle_pos)
    local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_pos)

    local vector_x = path_pos.x - vehicle_x
    local vector_z = path_pos.z - vehicle_z

    return math.sqrt( (vector_x * vector_x) + (vector_z * vector_z))
end

function normalize_2d(x, z)
    local xz_length = math.sqrt((x * x) + (z * z))
    return x / xz_length, z / xz_length
end

function get_angle(ax, az, bx, bz)
    local dot = (ax * bx) + (az * bz)
    dot = math.min(1, math.max(dot, -1))
    local radians = math.acos(dot)
    local perpendicular_dot = (az * bx) + (-ax * bz)
    if perpendicular_dot > 0 then
        return radians
    else
        return -radians
    end
end

function spawnObjects(spawn_transform, playlist_index, location_index, object_descriptors, out_spawned_objects)
    local spawned_objects = {}

    for _, object in pairs(object_descriptors) do
        -- find parent vehicle id if set

        local parent_vehicle_id = 0
        if object.vehicle_parent_component_id > 0 then
            for spawned_object_id, spawned_object in pairs(out_spawned_objects) do
                if spawned_object.type == "vehicle" and spawned_object.component_id == object.vehicle_parent_component_id then
                    parent_vehicle_id = spawned_object.id
                end
            end
        end

        spawnObject(spawn_transform, playlist_index, location_index, object, parent_vehicle_id, spawned_objects, out_spawned_objects)
    end

    return spawned_objects
end

function spawnObject(spawn_transform, playlist_index, location_index, object, parent_vehicle_id, spawned_objects, out_spawned_objects)
    -- spawn object

    local spawned_object_id = spawnObjectType(matrix.multiply(spawn_transform, object.transform), playlist_index, location_index, object, parent_vehicle_id)

    -- add object to spawned object tables

    if spawned_object_id ~= nil and spawned_object_id ~= 0 then

        local l_size = "small"
        for tag_index, tag_object in pairs(object.tags) do
            if string.find(tag_object, "size=") ~= nil then
                l_size = string.sub(tag_object, 6)
            end
        end

        local l_ai_type = "default"
        if hasTag(object.tags, "capability=hospital") then
            l_ai_type = "hospital"
        end
        if hasTag(object.tags, "type=ai_plane") then
            l_ai_type = "plane"
        end
        if hasTag(object.tags, "type=ai_heli") then
            l_ai_type = "heli"
        end

        local object_data = { type = object.type, id = spawned_object_id, component_id = object.id, size = l_size, ai_type = l_ai_type }

        if spawned_objects ~= nil then
            table.insert(spawned_objects, object_data)
        end

        if out_spawned_objects ~= nil then
            table.insert(out_spawned_objects, object_data)
        end

        return object_data
    end

    return nil
end

-- spawn an individual object descriptor from a playlist location
function spawnObjectType(spawn_transform, playlist_index, location_index, object_descriptor, parent_vehicle_id)
    local component = server.spawnAddonComponent(spawn_transform, playlist_index, location_index, object_descriptor.index, parent_vehicle_id)
    if component.type == "vehicle" then
        return component.vehicle_ids[1]
    end
    return component.object_id
end

-- iterator function for iterating over all playlists, skipping any that return nil data
function iterPlaylists()
    local playlist_count = server.getAddonCount()
    local playlist_index = 0

    return function()
        local playlist_data = nil
        local index = playlist_count

        while playlist_data == nil and playlist_index < playlist_count do
            playlist_data = server.getAddonData(playlist_index)
            index = playlist_index
            playlist_index = playlist_index + 1
        end

        if playlist_data ~= nil then
            return index, playlist_data
        else
            return nil
        end
    end
end

-- iterator function for iterating over all locations in a playlist, skipping any that return nil data
function iterLocations(playlist_index)
    local playlist_data = server.getAddonData(playlist_index)
    local location_count = 0
    if playlist_data ~= nil then location_count = playlist_data.location_count end
    local location_index = 0

    return function()
        local location_data = nil
        local index = location_count

        while location_data == nil and location_index < location_count do
            location_data = server.getLocationData(playlist_index, location_index)
            index = location_index
            location_index = location_index + 1
        end

        if location_data ~= nil then
            return index, location_data
        else
            return nil
        end
    end
end

-- iterator function for iterating over all objects in a location, skipping any that return nil data
function iterObjects(playlist_index, location_index)
    local location_data = server.getLocationData(playlist_index, location_index)
    local object_count = 0
    if location_data ~= nil then object_count = location_data.component_count end
    local object_index = 0

    return function()
        local object_data = nil
        local index = object_count

        while object_data == nil and object_index < object_count do
            object_data = server.getLocationComponentData(playlist_index, location_index, object_index)
            object_data.index = object_index
            index = object_index
            object_index = object_index + 1
        end

        if object_data ~= nil then
            return index, object_data
        else
            return nil
        end
    end
end

function hasTag(tags, tag)
    for k, v in pairs(tags) do
        if v == tag then
            return true
        end
    end

    return false
end

function spawnAircraft()
    if aircraft_count >= max_aircraft then
        log("aircraft limit reached")
        return
    end
    local random_location_index = math.random(1, #built_locations)
    local location = built_locations[random_location_index]
    local tries = 1
    while not isAircraft(location.ai_type) do
        random_location_index = math.random(1, #built_locations)
        location = built_locations[random_location_index]
        tries = tries + 1
        if tries >= 10 then
            log("failed to find an aircraft prefab")
            return
        end
    end
    local random_transform = matrix.translation(math.random(location.objects.vehicle.bounds.x_min, location.objects.vehicle.bounds.x_max), 0, math.random(location.objects.vehicle.bounds.z_min, location.objects.vehicle.bounds.z_max))

    local spawn_transform, is_success =  server.getOceanTransform(random_transform, 1000, 10000)
    spawn_transform = matrix.multiply(spawn_transform, matrix.translation(math.random(-500, 500), aircraft_start_height, math.random(-500, 500)))

    if is_success then
        local all_mission_objects = {}
        local spawned_objects = {
            vehicle = spawnObject(spawn_transform, location.playlist_index, location.location_index, location.objects.vehicle, 0, nil, all_mission_objects),
            survivors = spawnObjects(spawn_transform, location.playlist_index,location.location_index, location.objects.survivors, all_mission_objects),
            objects = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.objects, all_mission_objects),
            zones = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.zones, all_mission_objects)
        }


        g_savedata.vehicles[spawned_objects.vehicle.id] = {survivors = spawned_objects.survivors, path = {}, state = { s = "pathing", timer = math.fmod(spawned_objects.vehicle.id, 300), is_simulating = false }, ui_id = server.getMapID(), map_id = server.getMapID(), ai_type = spawned_objects.vehicle.ai_type, bounds = location.objects.vehicle.bounds, current_damage = 0, despawn_timer = 0}
        createAircraftPath(spawned_objects.vehicle.id)
        local char_id = spawned_objects.survivors[1].id
        local c = server.getCharacterData(char_id)
        server.setCharacterData(char_id, c.hp, false, true)
        server.setAIState(char_id, 1)
    end
end

function spawnVessel()
    if vessel_count >= max_vessel then
        log("vessel limit reached")
        return
    end
    local random_location_index = math.random(1, #built_locations)
    local location = built_locations[random_location_index]
    local tries = 1
    while isAircraft(location.ai_type) do
        random_location_index = math.random(1, #built_locations)
        location = built_locations[random_location_index]
        tries = tries + 1
        if tries >= 10 then
            log("failed to find a vessel prefab")
            return
        end
    end
    local random_transform = matrix.translation(math.random(location.objects.vehicle.bounds.x_min, location.objects.vehicle.bounds.x_max), 0, math.random(location.objects.vehicle.bounds.z_min, location.objects.vehicle.bounds.z_max))

    local spawn_transform, is_success =  server.getOceanTransform(random_transform, 1000, 10000)
    spawn_transform = matrix.multiply(spawn_transform, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))

    if is_success then
        local all_mission_objects = {}
        local spawned_objects = {
            vehicle = spawnObject(spawn_transform, location.playlist_index, location.location_index, location.objects.vehicle, 0, nil, all_mission_objects),
            survivors = spawnObjects(spawn_transform, location.playlist_index,location.location_index, location.objects.survivors, all_mission_objects),
            objects = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.objects, all_mission_objects),
            zones = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.zones, all_mission_objects)
        }


        g_savedata.vehicles[spawned_objects.vehicle.id] = {survivors = spawned_objects.survivors, destination = { x = 0, z = 0 }, path = {}, map_id = server.getMapID(), state = { s = "pseudo", timer = math.fmod(spawned_objects.vehicle.id, 300) }, bounds = location.objects.vehicle.bounds, size = spawned_objects.vehicle.size, current_damage = 0, despawn_timer = 0, ai_type = spawned_objects.vehicle.ai_type }
        local char_id = spawned_objects.survivors[1].id
        local c = server.getCharacterData(char_id)
        server.setCharacterData(char_id, c.hp, false, true)
        server.setAIState(char_id, 1)
    end
end

function isAircraft(ai_type)
    return ai_type == "heli" or ai_type == "plane"
end

function announce(message)
    server.announce("hostile_ai", message)
end

function log(message)
    if not debug_mode then
        return
    end
    server.announce("hostile_ai", "DEBUG:" .. message)
end

function isTickID(id, rate)
    return (tick_counter + id) % rate == 0
end
