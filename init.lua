local playerstuff = {

}

SLOWBUILD_ENABLED = minetest.settings:get("SLOWBUILD_ENABLED") or false

local server_place_que = {}

local canceled = {}

local player_place_que = {}

local function get_node_cap(player, node) --- calculate how many items of a certain node a player has in inventory
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
    local p1p2dist = vector.distance(pos1, pos2)
    local p1p2dir = vector.direction(pos1, pos2)


    -- Modify data
    for z = pos1.z, pos2.z do
      for y = pos1.y, pos2.y do
        for x = pos1.x, pos2.x do
          tick = tick + 1
          local vi = a:index(x, y, z)
          if has_value(replace, data[vi]) then -- make sure we are placing on placeable ground
            if tick > cap then break end
            local pos = vector.new(x,y,z)
            if SLOWBUILD_ENABLED then
              table.insert(server_place_que[placer][que_table_name], {vector.new(x,y,z), node})
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

    take_items(placer, node, (luaentity.volume or 0)-use_less)
    if not SLOWBUILD_ENABLED then
      -- Write data
      vm:set_data(data)
      vm:set_param2_data(param2data)
      vm:write_to_map(true)
    end
    playerstuff[placer]:remove()
    playerstuff[placer] = nil

    for _,thenode in ipairs(server_place_que[placer][que_table_name]) do
      minetest.after(math.random(100)/80+(((luaentity.volume or 0)-use_less)/3000), function()
        minetest.set_node(thenode[1], thenode[2])
      end)
    end

    return true
  end
end

minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing) -- preventive placing when using

  local ctrl = placer:get_player_control()

  if not playerstuff[placer] and not (ctrl.RMB and ctrl.aux1) then return end

  minetest.remove_node(pos)
  return true
end)

local function get_look_place(player, dir) -- gets the exact loctaion that a player is looking (with raycast)

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
      return hitpoint.above
    end
  end
  return mousepos
end
local thing_hud = {}

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
  if not minetest.registered_nodes[item] then return end
  local obj = minetest.add_entity(vector.subtract(get_look_place(player), vector.new(0.5,0.5,0.5)), "mt_build_easy:box")
  obj:get_luaentity()._player = player

  obj:get_luaentity()._original_pos = vector.round(get_look_place(player))
  obj:get_luaentity()._node = {name=item, param2=minetest.dir_to_facedir(
    get_look_place(player, true)
  , true)}
  playerstuff[player] = obj
end)

controls.register_on_press(function(player, key)
  if key == "RMB" then canceled[player] = false end
  if key ~= "LMB" or not playerstuff[player] then return end
  playerstuff[player]:remove()
  playerstuff[player] = nil
  canceled[player] = true
  if thing_hud[player] then
    player:hud_remove(thing_hud[player])
  end
end)


local function set_view_hud(player, thing)
  -- shows how much of the certain material you have while also doing a general
  -- calculation based on the volume of selected area to determine how much is
  -- going to be used (does not account for obstructions as that could easily
  -- slow the game down if the box gets too big)
  if thing_hud[player] then
    player:hud_remove(thing_hud[player])
  end

  local cap = get_node_cap(player, thing._node)

  local fontcolor = 0x22ff22
  if thing.volume > cap then fontcolor = 0xff2222 end

  thing_hud[player] = player:hud_add({
      hud_elem_type = "text",
      position = {x=0.5, y=1},
      scale = {x = 1, y = 1},
      text = "Volume: "..thing.volume.."/"..cap.."\nPunch to cancel.",
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
  on_step = function(self)
    if not self._player or not self._original_pos then return end



    local mousepos = vector.add(get_look_place(self._player), vector.new(0.5,0.5,0.5))

    --local pos = vector.add(self.object:get_pos(), vector.new(0.5,0.5,0.5))
    local pos = self._original_pos
    local ppos = vector.round(vector.add(mousepos, vector.new(0.5,0.5,0.5)))
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

    self.object:set_properties({
      visual_size = vector.multiply(fake_size, 5),
    })

    if ppos == self._old_ppos then return end
    self._old_ppos = ppos

    local dis = vector.distance(pos, ppos)
    local dir = vector.direction(pos, ppos)
    local size = vector.new(dis*-dir.x+1, dis*dir.y, dis*-dir.z+1)


    npos = table.copy(pos)
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

    local d = vector.round(ppos)

    self.volume =
      math.abs(math.abs(size.x))*
      math.abs(math.abs(size.y))*
      math.abs(math.abs(size.z))

    local textures = self.object:get_properties().textures
    if self.volume > get_node_cap(self._player, self._node) and textures[1] ~= "half_red.png" then
      self.object:set_properties({textures={"half_red.png"}})
    elseif self.volume <= get_node_cap(self._player, self._node) and textures[1] ~= "half_green.png" then
      self.object:set_properties({textures={"half_green.png"}})
    end

    set_view_hud(self._player, self)
    self._size = size

    self._to_pos = mousepos

    if negitives % 2 == 0 then
      self.object:set_properties({
        mesh = "selectionbox.obj",
      })
    else
      self.object:set_properties({
        mesh = "selectionbox_flipped.obj",
      })
    end
    self.object:set_pos(npos)

  end
})



minetest.register_globalstep(function(dtime)

end)
