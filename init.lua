local playerstuff = {}

local building_schem = {}
local building_schem_index = {}

local material_hud = {}


local schem_create_pos = {}

local MAXVOLUMECOPY = minetest.settings:get("MAXVOLUMECOPY") or 10000

local SLOWBUILD_ENABLED = minetest.settings:get("SLOWBUILD_ENABLED") or false

local server_place_que = {}

local canceled = {}

local player_place_que = {}

local function get_node_cap(player, node) --- calculate how many items of a certain node a player has in inventory
  if node.name == "air" then return MAXVOLUMECOPY end
  if minetest.is_creative_enabled(player:get_player_name()) then return 100000000 end
  local cap = 0
  local inv = player:get_inventory()
  for i=1, inv:get_size("main") do
    local it = inv:get_stack("main", i)
    if not it:is_empty() and it:get_name() == node.name then
      cap = cap+it:get_count()
    end
  end
  return cap
end

local function take_items(player, node, amount) -- take a certain amount from multiple stacks if needed from a players inventory
  if minetest.is_creative_enabled(player:get_player_name()) then return end
  local amount_left = amount
  local inv = player:get_inventory()
  for i=1, inv:get_size("main") do
    local it = inv:get_stack("main", i)
    if not it:is_empty() and it:get_name() == node.name then
      if amount_left < it:get_count() then
        it:take_item(amount_left)
        inv:set_stack("main", i, it)
        break
      else
        it:take_item(it:get_count())
        inv:set_stack("main", i, it)
        amount_left = amount_left-it:get_count()
      end
    end
  end
end

local function has_value (tab, val) -- generic "in list" function
  for index, value in ipairs(tab) do
    if value == val then
      return true
    end
  end

  return false
end


local function get_look_place(player, dir, inside_node) -- gets the exact loctaion that a player is looking (with raycast)

  if not player then
    return
  end

  local reach = minetest.registered_items[player:get_wielded_item():get_name()].range or minetest.registered_items[""].range or 4

  local mousepos = vector.add(vector.add(vector.multiply(player:get_look_dir(), reach), vector.new(0,player:get_properties().eye_height,0)), player:get_pos())
  local view = vector.add(vector.new(0,player:get_properties().eye_height,0), player:get_pos())

  if dir then return vector.direction(view, mousepos) end

  local raycast = minetest.raycast(view, mousepos, false, false)
  for hitpoint in raycast do
    if hitpoint.type == "node" then
      if inside_node then
        return hitpoint.under
      else
        return hitpoint.above
      end
    end
  end
  return mousepos
end
local thing_hud = {}



local function build_form(itemstack, user, pointed_thing, formextra) -- pick schem to place

  local directory = minetest.get_dir_list(minetest.get_worldpath().."/"..user:get_player_name().."s_build_schems")

  if not directory or building_schem[user] then return end

  slist = "textlist[0.5,1;7,7;schemslist;"..table.concat(directory,","):gsub(".mts", "")..";nil;false]"

	local formspec =
    "formspec_version[4]"..
    "size[8,8]"..

    "background[-0.5,-0;9,9;mt_bg.png]"..
    slist..


    --"image[2.4,6.9;3.2,1.2;mt_black.png]"..
    "image_button_exit[4.5,7;3,1;mt_button.png;close;Close]"..
    "image_button_exit[0.5,7;3,1;mt_button.png;submit;Ok]"..(formextra or "")
	minetest.show_formspec(user:get_player_name(), "mt_build_easy:pick_schem", formspec)
end


local function naming_build_form(user) -- pick schem to place

  local directory = minetest.get_dir_list(minetest.get_worldpath().."/"..user:get_player_name().."s_build_schems")

  if not directory or building_schem[user] then return end
  local slist = "field[mts_name;Structure Name;]"

	local formspec =
    "formspec_version[4]"..
    "size[8,5]"..
    slist..
    "background[-0.5,-0;9,6;mt_bg.png]"

	minetest.show_formspec(user:get_player_name(), "mt_build_easy:name_schem", formspec)
end


minetest.register_on_player_receive_fields(function(player, formname, fields)


  if formname == "mt_build_easy:name_schem" then
    if not fields[fields.key_enter_field] or fields[fields.key_enter_field] == "" or fields[fields.key_enter_field] == " " then
      minetest.chat_send_player(player:get_player_name(), minetest.colorize("#f22", "Failed to save structure! Invalid Name."))
    else

      local path = minetest.get_worldpath().."/"..player:get_player_name().."s_build_schems"
      -- Create directory if it does not already exist
      minetest.mkdir(path)


      local filename = path .. "/" .. fields[fields.key_enter_field] .. ".mts"
      os.remove(filename)
      if not schem_create_pos[player] then return end
      local ret = minetest.create_schematic(schem_create_pos[player][1], schem_create_pos[player][2], nil, filename)
      if ret == nil then
        minetest.chat_send_player(player:get_player_name(), minetest.colorize("#f22", "Failed to save structure!"))
      else
        minetest.chat_send_player(player:get_player_name(), minetest.colorize("#2f2", "Structure saved!"))
      end
    end
  end




  if formname ~= "mt_build_easy:pick_schem" then return end

  local path = minetest.get_worldpath().."/"..player:get_player_name().."s_build_schems"

  local directory = minetest.get_dir_list(path)

  if not directory or not path then return end

  if fields["submit"] and building_schem_index[player] then


    local obj = minetest.add_entity(vector.subtract(get_look_place(player), vector.new(0.5,0.5,0.5)), "mt_build_easy:box")
    local luaentity = obj:get_luaentity()
    luaentity._player = player

    luaentity._schem = minetest.read_schematic(path.."/"..directory[building_schem_index[player]], {})
    luaentity._materials = {}
    for key,node in ipairs(luaentity._schem.data) do
      if node.name ~= "air" and node.name ~= "ignore" then
        luaentity._materials[node.name] = luaentity._materials[node.name] or 0
        luaentity._materials[node.name] = luaentity._materials[node.name] + 1
      end
    end
    luaentity._schem_name = directory[building_schem_index[player]]
    building_schem[player] = obj

    building_schem_index[player] = nil
  end

  if not fields['schemslist'] then return end



  building_schem_index[player] = tonumber(fields['schemslist']:sub(5,-1))


end)

local function rotate_pos(pos, rot, weird_exeption)
  if not weird_exeption then
    weird_exeption = 1
  else
    weird_exeption = -1
  end

  --print(dir)
  if rot == 0 or rot == 360 then
    pos = pos
  elseif rot == 90 then
    pos = vector.new(math.abs(pos.z), pos.y, -math.abs(pos.x)+2)
    --self._schempos = vector.add(ppos, vector.new(-4,0,0))
  elseif rot == 180 then
    pos = vector.new(-math.abs(pos.x)+2, pos.y, -math.abs(pos.z)+2)
    --self._schempos = vector.add(ppos, vector.new(0,0,-4))
  else
    pos = vector.new(-math.abs(pos.z)+2, pos.y, math.abs(pos.x))
    --self._schempos = vector.add(ppos, vector.new(0,0,0))
  end
  return pos
end

local function place_schem(player, pos, path, rot, schem_load)

  if rot == 90 then
    pos.z=pos.z-2
  elseif rot == 180 then
    pos.z=pos.z-2
    pos.x=pos.x-2
  elseif rot == 270 then
    pos.x=pos.x-2
  end


  local size = vector.new(rotate_pos(schem_load.size, rot, true))


  local pos1, pos2 = pos, vector.add(pos, size)


  local replace = {}

  for name,def in pairs(minetest.registered_nodes) do
    if def.buildable_to then
      table.insert(replace, minetest.get_content_id(name))
    end
  end


  local placers = {}
  local node_ticks = {}
  local node_caps = {}


  if true then
    for key,node in pairs(schem_load.data) do

      if not node_ticks[node.name] then
        node_ticks[node.name] = 0
      end
      if not node_caps[node.name] then
        node_caps[node.name] = get_node_cap(player, node)
      end

      if node.name ~= "air" and node.name ~= "ignore" then
        placers[node.name] = placers[node.name] or 0
        placers[node.name] = placers[node.name] + 1
      end
    end
  end

  local c_stuff  = minetest.get_content_id("air")
  -- Read data into LVM
  local vm = minetest.get_voxel_manip()
  local emin, emax = vm:read_from_map(pos1, pos2)
  local a = VoxelArea:new{
      MinEdge = emin,
      MaxEdge = emax
  }
  local data = vm:get_data()
  local param2data = vm:get_param2_data()

  local tick = 0



  --local size = rotate_schem(schem_load.size, rot)

  local que_table_name = tostring(math.random(10000))
  server_place_que[player] = server_place_que[player] or {}
  server_place_que[player][que_table_name] = {}

  --local cap = get_node_cap(player, node)
  local use_less = 0
  local p1p2dist = vector.distance(pos1, pos2)
  local p1p2dir = vector.direction(pos1, pos2)

  local loop1 = vector.new(0,0,0)
  local loop2 = vector.new(schem_load.size.z-1,schem_load.size.y-1,schem_load.size.x-1)

  loop1, loop2 = vector.sort(loop1, loop2)



  -- Modify data
  for zs = loop1.x, loop2.x do
    for ys = loop1.y, loop2.y do
      for xs = loop1.z, loop2.z do
        local ns = rotate_pos(vector.new(xs,ys,zs), rot, true)
        local x,y,z=ns.x+pos.x, ns.y+pos.y, ns.z+pos.z
        tick = tick + 1

        local thisnode = schem_load.data[tick].name
        node_ticks[thisnode] = node_ticks[thisnode]+1

        local vi = a:index(x, y, z)
        if not (node_ticks[thisnode] > node_caps[thisnode]) then

          if has_value(replace, data[vi]) then -- make sure we are placing on placeable ground
              local pos = vector.new(x,y,z)
              --param2data[vi] = node.param2

              if SLOWBUILD_ENABLED then
                minetest.after((ns.y*300+ns.z*math.random(8,20)+ns.x*math.random(8,10))/1000, function()
                  minetest.set_node(vector.new(x,y,z), {name=thisnode})
                end)
              else

                --minetest.get_player_by_name("singleplayer"):set_pos(vector.new(x,y,z))
                data[vi] = minetest.get_content_id(schem_load.data[tick].name)
              end
          else
            node_ticks[thisnode] = node_ticks[thisnode]-1
            if placers[thisnode] then
              placers[thisnode] = placers[thisnode]-1 -- one less block to be taken from player if not able to place
            else
              print(thisnode)
            end
          end

        end
      end
    end
  end

  for node,amount in pairs(placers) do
    take_items(player, {name=node}, amount)
  end

  if not SLOWBUILD_ENABLED then
    -- Write data
    vm:set_data(data)
    vm:set_param2_data(param2data)
    vm:write_to_map(true)
  end
  return true
end

local function on_place_schem(itemstack, placer, pointed_thing)
  local path = minetest.get_worldpath().."/"..placer:get_player_name().."s_build_schems"
  if not building_schem[placer] then return end
  local luaentity = building_schem[placer]:get_luaentity()
  if not luaentity then return end
  local rot = math.round(math.deg(placer:get_look_horizontal())/90)*90
  place_schem(placer, luaentity._schempos, path.."/"..luaentity._schem_name, (luaentity._rotation or 0), luaentity._schem)
  --building_schem[placer]:remove()
  --building_schem[placer] = nil
  if material_hud[placer] then
    for key,index in pairs(material_hud[placer]) do
      placer:hud_remove(index[1])
      placer:hud_remove(index[2])
      material_hud[placer] = nil
    end
  end
end


minetest.register_tool("mt_build_easy:copytool", {
  description = "Structor\n"..minetest.colorize("#288e49", "A tool used to copy structures effortlessly.\nUse+Place and drag to copy any group of nodes"),
  inventory_image = "mt_build_easy_copytool.png",
  groups = {},
  on_use = function(itemstack, user, pointed_thing)
    if building_schem[player] then return end
    build_form(itemstack, user, pointed_thing)
    --naming_build_form(user)
  end,
  on_secondary_use = on_place_schem,
  on_place = on_place_schem,
})


local function make_new_schem(pos1, pos2, player)
  schem_create_pos[player] = {pos1, pos2}

  naming_build_form(player)

end

local function place_stuff(node, placer) -- the function to place the nodes in selected area defined by the entitie's "self" data
  if playerstuff[placer] then
    local luaentity = playerstuff[placer]:get_luaentity()
    if not luaentity then return end




    node = node or {name=luaentity._node.name, param2=luaentity._node.param2}
    local c_stuff  = minetest.get_content_id(luaentity._node.name)

    local replace = {}

    for name,def in pairs(minetest.registered_nodes) do
      if def.buildable_to then
        table.insert(replace, minetest.get_content_id(name))
      end
    end


    local pos1, pos2 = vector.sort(vector.floor(luaentity._original_pos), vector.floor(luaentity._to_pos))
    --    local pos1, pos2 = luaentity._original_pos, luaentity._to_pos

    if luaentity._node.name == "air" then -- if using copytool then
      make_new_schem(pos1, pos2, placer)
      playerstuff[placer]:remove()
      playerstuff[placer] = nil

      return
    end


    -- Read data into LVM
    local vm = minetest.get_voxel_manip()
    local emin, emax = vm:read_from_map(pos1, pos2)
    local a = VoxelArea:new{
        MinEdge = emin,
        MaxEdge = emax
    }
    local data = vm:get_data()
    local param2data = vm:get_param2_data()

    local tick = 0

    local que_table_name = tostring(math.random(10000))
    server_place_que[placer] = server_place_que[placer] or {}
    server_place_que[placer][que_table_name] = {}

    local cap = get_node_cap(placer, node)
    local use_less = 0
    local p1p2dist = vector.distance(luaentity._original_pos, luaentity._ppos)
    local p1p2dir = vector.direction(luaentity._original_pos, luaentity._ppos)
    --local line = true

    if line then
      for i=1, p1p2dist do
        print("s")
        local newpos = vector.round(vector.add(luaentity._original_pos, vector.multiply(p1p2dir,i)))
        local vi = a:index(newpos.x, newpos.y, newpos.z)
        local opos = vector.subtract(newpos,luaentity._original_pos)
        if SLOWBUILD_ENABLED then
          minetest.after(((opos.y)*300+opos.z*math.random(16,20)+opos.x*math.random(5,8))/1000, function()
            minetest.set_node(newpos, node)
          end)
        else
          param2data[vi] = node.param2
          data[vi] = c_stuff
        end
      end
    else
      -- Modify data
      for z = pos1.z, pos2.z do
        for y = pos1.y, pos2.y do
          for x = pos1.x, pos2.x do
            tick = tick + 1
            local vi = a:index(x, y, z)
            if has_value(replace, data[vi]) then -- make sure we are placing on placeable ground
              local opos = vector.subtract(vector.new(x,y,z),pos1)
              if tick > cap then break end
              local pos = vector.new(x,y,z)
              if SLOWBUILD_ENABLED then
                minetest.after(((opos.y)*300+opos.z*math.random(16,20)+opos.x*math.random(5,8))/1000, function()
                  minetest.set_node(vector.new(x,y,z), node)
                end)
              else
                param2data[vi] = node.param2
                data[vi] = c_stuff
              end
            else
              tick = tick-1
              use_less = use_less+1 -- one less block to be taken from player if not able to place
            end
          end
          if tick > cap then break end
        end
        if tick > cap then break end
      end
    end

    take_items(placer, node, (luaentity.volume or 0)-use_less)
    if not SLOWBUILD_ENABLED then
      -- Write data
      vm:set_data(data)
      vm:set_param2_data(param2data)
      vm:write_to_map(true)
    end
    playerstuff[placer]:remove()
    playerstuff[placer] = nil

    return true
  end
end

minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing) -- preventive placing when using

  local ctrl = placer:get_player_control()

  if not playerstuff[placer] and not (ctrl.RMB and ctrl.aux1) then return end
  minetest.remove_node(pos)
  return true
end)


controls.register_on_release(function(player, key)
  if key ~= "RMB" then return end
  canceled[player] = false
  if not playerstuff[player] then return else
    player_place_que = {}
  end
  place_stuff(nil, player)
  if thing_hud[player] then
    player:hud_remove(thing_hud[player])
  end
end)

controls.register_on_hold(function(player, key, time)
  if key ~= "RMB" or not player:get_player_control().aux1 or canceled[player] then return end
  if playerstuff[player] then return end
  local item = player:get_wielded_item():get_name()
  local copytool, copy
  if item == "mt_build_easy:copytool" then
    item = "air"
    copy = true
    copytool = true
  end
  if not minetest.registered_nodes[item] then return end
  local obj = minetest.add_entity(vector.subtract(get_look_place(player, false, copytool), vector.new(0.5,0.5,0.5)), "mt_build_easy:box")
  obj:get_luaentity()._player = player
  obj:get_luaentity()._copy = copy

  obj:get_luaentity()._original_pos = vector.round(get_look_place(player, false, copytool))
  obj:get_luaentity()._node = {name=item, param2=minetest.dir_to_facedir(
    get_look_place(player, true)
  , true)}
  playerstuff[player] = obj
end)

controls.register_on_press(function(player, key)
  if key == "RMB" then canceled[player] = false end

  if key == "aux1" and player:get_player_control().sneak and building_schem[player] then
    building_schem[player]:get_luaentity().rotate(building_schem[player]:get_luaentity())
  end

  if key ~= "LMB" or not (playerstuff[player] or building_schem[player]) then return end
  if building_schem[player] then
    building_schem[player]:remove()
    building_schem[player] = nil
  else
    playerstuff[player]:remove()
    playerstuff[player] = nil
  end
  canceled[player] = true
  if thing_hud[player] then
    player:hud_remove(thing_hud[player])
  end
  if material_hud[player] then
    for key,index in pairs(material_hud[player]) do
      player:hud_remove(index[1])
      player:hud_remove(index[2])
      material_hud[player] = nil
    end
  end
end)


local function set_view_hud(player, thing, materials)
  -- shows how much of the certain material you have while also doing a general
  -- calculation based on the volume of selected area to determine how much is
  -- going to be used (does not account for obstructions as that could easily
  -- slow the game down if the box gets too big)
  if thing_hud[player] then
    player:hud_remove(thing_hud[player])
    thing_hud[player] = nil
  end
  if material_hud[player] then
    for key,index in pairs(material_hud[player]) do
      player:hud_remove(index[1])
      player:hud_remove(index[2])
      material_hud[player] = nil
    end
  end



  if materials then
    local text = "\nPunch to cancel."

    local tick = 0
    for node,amount in pairs(materials) do
      local fontcolor = 0x22dd22
      local cap = get_node_cap(player, {name=node})
      if amount > cap then fontcolor = 0xff2222 end
      tick = tick + 1
      local coolnode = minetest.registered_nodes[node].description or "UNKNOWN"
      material_hud[player] = material_hud[player] or {}
      material_hud[player][node] = material_hud[player][node] or {}
      material_hud[player][node][1] = player:hud_add({
          hud_elem_type = "text",
          position = {x=0, y=0},
          scale = {x = 1, y = 1},
          text = coolnode..":",
          number = fontcolor,
          alignment = {x=-1, y=0},
          offset = {x=150, y=120+(tick*20)},
          z_index = 110,
          style = 0,
      })
      material_hud[player][node][2] = player:hud_add({
          hud_elem_type = "text",
          position = {x=0, y=0},
          scale = {x = 1, y = 1},
          text = cap.."/"..amount,
          number = fontcolor,
          alignment = {x=1, y=0},
          offset = {x=155, y=120+(tick*20)},
          z_index = 110,
          style = 0,
      })
    end
    return
  end

  local cap = get_node_cap(player, thing._node)

  local fontcolor = 0x22dd22

  local text = "Volume: "..thing.volume.."/"..cap.."\nPunch to cancel."

  if thing.volume > cap then fontcolor = 0xff2222 end

  thing_hud[player] = player:hud_add({
      hud_elem_type = "text",
      position = {x=0.5, y=1},
      scale = {x = 1, y = 1},
      text = text,
      number = fontcolor,
      item = 0,
      direction = 0,
      alignment = {x=0, y=0},
      offset = {x=0, y=-100},
      world_pos = {x=0, y=0, z=0},
      size = {x=0, y=0},
      z_index = 110,
      style = 0,
  })
end


minetest.register_entity("mt_build_easy:box", {
  visual = "mesh",
  mesh = "selectionbox.obj",
  textures = {"half_green.png"},
  _player = nil,
  _node = {name="air"},
  pointable = false,
  use_texture_alpha = true,
  volume = 0,
  _to_pos = vector.new(0,0,0),
  _scale_pos = vector.new(0,0,0),
  _old_ppos = vector.new(0,0,0),
  _size = vector.new(0,0,0),
  _original_pos = vector.new(0,0,0),
  _ppos = vector.new(0,0,0),
  --_line = true,
  on_activate = function(self)
    minetest.after(0.1, function()
      if not self._player then
        self.object:remove()
      end
    end)
  end,
  on_step = function(self)
    if not self._player then return end

    local copytool

    if self._copy then copytool = true end

    local mousepos = vector.add(get_look_place(self._player, false, copytool), vector.new(0.5,0.5,0.5))
    local ppos = vector.round(vector.add(mousepos, vector.new(0.5,0.5,0.5)))


    if self._schem then
      ppos = vector.add(ppos, vector.new(-1,-1,-1))
      self._original_pos = ppos
      self._schempos = ppos
      local dir = self._rotation
      local size = self._schem.size
      size = rotate_pos(size, dir)
      self._sizze = size
      --minetest.chat_send_all(vector.to_string(size))

      --print(dir)
      --[[
      if dir == 0 or dir == 360 then
        size = size
      elseif dir == 90 then
        size = vector.new(-size.z+2, size.y, size.x)
        --self._schempos = vector.add(ppos, vector.new(-4,0,0))
      elseif dir == 180 then
        size = vector.new(size.x, size.y, -size.z+2)
        --self._schempos = vector.add(ppos, vector.new(0,0,-4))
      else
        size = vector.new(size.z, size.y, size.x)
        --self._schempos = vector.add(ppos, vector.new(0,0,0))
      end]]
      ppos = vector.add(ppos, size)
    end




    --local pos = vector.add(self.object:get_pos(), vector.new(0.5,0.5,0.5))
    local pos = self._original_pos
    --local ppos = self._player:get_pos()


    local current_size = vector.divide(self.object:get_properties().visual_size, 5)
    local fake_size = vector.add(
      self._size,
      vector.multiply(vector.subtract(current_size, self._size), 0.5)
    )

    local negitives = 0
    for _,num in pairs(self._size) do
      if num/(math.abs(num)) == -1 then
        negitives = negitives + 1
      end
    end

    self._ppos = ppos
    if self._line then
      fake_size = vector.new(1, 1, -vector.distance(pos, ppos)*2)
      self.object:set_rotation(vector.dir_to_rotation(vector.direction(pos, ppos)))
    end

    self.object:set_properties({
      visual_size = vector.multiply(fake_size, 5),
    })


    local dis = vector.distance(pos, ppos)
    local dir = vector.direction(pos, ppos)
    local size = vector.new(dis*-dir.x+1, dis*dir.y, dis*-dir.z+1)

    local npos = table.copy(pos)
    if size.x <= 0 then
      size.x = size.x-1
      npos.x = npos.x - 0.5
    else
      size.x = size.x+1
      npos.x = npos.x + 0.5
    end
    if size.y <= 0 then
      size.y = size.y-2
      npos.y = npos.y + 0.5
    else
      size.y = size.y
      npos.y = npos.y - 0.5
    end
    if size.z <= 0 then
      size.z = size.z-1
      npos.z = npos.z - 0.5
    else
      size.z = size.z+1
      npos.z = npos.z + 0.5
    end


    if not self._line then
      local spos = self.object:get_pos()
      self.object:set_pos(vector.add(spos, vector.divide(vector.subtract(npos,spos), 3)))
    end

    if ppos == self._old_ppos then return end
    self._old_ppos = ppos


    local d = vector.round(ppos)

    self.volume =
      math.abs(math.abs(size.x))*
      math.abs(math.abs(size.y))*
      math.abs(math.abs(size.z))

    local textures = self.object:get_properties().textures
    if self._node.name == "air" and self._copy then
      self.object:set_properties({textures={"half_copy.png"}})
    elseif self._node.name == "air" and not self._copy or self._schem then
      self.object:set_properties({textures={"half_place.png"}})
    elseif self.volume > get_node_cap(self._player, self._node) and textures[1] ~= "half_red.png" then
      self.object:set_properties({textures={"half_red.png"}})
    elseif self.volume <= get_node_cap(self._player, self._node) and textures[1] ~= "half_green.png" then
      self.object:set_properties({textures={"half_green.png"}})
    end

    set_view_hud(self._player, self, self._materials)
    self._size = size

    self._to_pos = mousepos

    if self._line then
      self.object:set_properties({
        mesh = "selectionbox_line.obj",
      })
    elseif negitives % 2 == 0 then
      self.object:set_properties({
        mesh = "selectionbox.obj",
      })
    else
      self.object:set_properties({
        mesh = "selectionbox_flipped.obj",
      })
    end


  end,
  _rotation = 0,
  rotate = function(self)
    self._rotation = (self._rotation + 90)%360
    print(self._rotation)
  end,

  glow = 2,
})



minetest.register_globalstep(function(dtime)

end)
