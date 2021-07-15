-- Persistent Configuration --

local storage = minetest.get_mod_storage()

local function get_or_default(key, default)
	if storage:contains(key) then
		return storage:get_int(key)
	else
		storage:set_int(key, default)
		return default
	end
end

local INSIDE_SPACING = get_or_default("INSIDE_SPACING", 32)
local Y_LEVEL = get_or_default("Y_LEVEL", -28800)
local X_BASE = get_or_default("X_BASE", -28800)
local Z_BASE = get_or_default("Z_BASE", -28800)
local param1_next = get_or_default("param1_next", 1) -- Leave zero for null.
local param2_next = get_or_default("param2_next", 0)

local relation_containers = {}

-- Parameter Interpretation --

local function get_index(param1, param2)
	return param1 + param2 * 256
end

local function get_related_inside(param1, param2)
	return vector.new(
		X_BASE + param1 * INSIDE_SPACING,
		Y_LEVEL,
		Z_BASE + param2 * INSIDE_SPACING
	)
end
area_containers.get_related_inside = get_related_inside

function area_containers.params_are_null(param1, param2)
	return param1 == 0 and param2 == 0
end

-- Parameter String Encoding and Decoding --

local seg2char = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+-"
assert(#seg2char == 64)
local char2seg = {}
for i = 1, #seg2char do
	char2seg[string.sub(seg2char, i, i)] = i - 1
end

local PARAMS_STRING_LENGTH = 3

local function params_to_string(param1, param2)
	local seg1 = param1 % 64
	local seg2 = param2 % 64
	local seg3 = math.floor(param1 / 64) + math.floor(param1 / 64) * 4
	return string.sub(seg2char, seg1 + 1, seg1 + 1) ..
		string.sub(seg2char, seg2 + 1, seg2 + 1) ..
		string.sub(seg2char, seg3 + 1, seg3 + 1)
end

local function string_to_params(str)
	local seg1 = char2seg[string.sub(str, 1, 1)]
	local seg2 = char2seg[string.sub(str, 2, 2)]
	local seg3 = char2seg[string.sub(str, 3, 3)]
	local param1 = seg1 + (seg3 % 4) * 64
	local param2 = seg2 + math.floor(seg3 / 4) * 64
	return param1, param2
end

-- Allocation and Deallocation --

function area_containers.alloc_relation()
	local param1, param2
	local freed = storage:get_string("freed")
	if #freed >= PARAMS_STRING_LENGTH then
		param1, param2 = string_to_params(
			string.sub(freed, -PARAMS_STRING_LENGTH))
		freed = string.sub(freed, 1, #freed - PARAMS_STRING_LENGTH)
		storage:set_string("freed", freed)
	elseif param2_next < 256 then
		param1 = param1_next
		param2 = param2_next
		param1_next = param1_next + 1
		if param1_next >= 256 then
			param1_next = 0
			param2_next = param2_next + 1
		end
		storage:set_int("param1_next", param1_next)
		storage:set_int("param2_next", param2_next)
	end
	return param1, param2
end

function area_containers.free_relation(param1, param2)
	local freed = storage:get_string("freed")
	freed = freed .. params_to_string(param1, param2)
	storage:set_string("freed", freed)
	relation_containers[get_index(param1, param2)] = nil
end

function area_containers.reclaim_relation(param1, param2)
	local find_params = params_to_string(param1, param2)
	local freed = storage:get_string("freed")
	if string.sub(freed, -PARAMS_STRING_LENGTH) == find_params then
		freed = string.sub(freed, 1, #freed - PARAMS_STRING_LENGTH)
		storage:set_string("freed", freed)
		return true
	end
	for i = 1, #freed - PARAMS_STRING_LENGTH + 1, PARAMS_STRING_LENGTH do
		local start = -i - PARAMS_STRING_LENGTH + 1
		local finish = -i
		local check_params = string.sub(freed, start, finish)
		if check_params == find_params then
			freed = string.sub(freed, 1, start - 1) ..
				string.sub(freed, finish + 1)
			storage:set_string("freed", freed)
			return true
		end
	end
	return false
end


-- Related Container Handling --

function area_containers.get_related_container(param1, param2)
	local idx = get_index(param1, param2)
	local container_pos = relation_containers[idx]
	if not container_pos then
		local inside_pos = get_related_inside(param1, param2)
		local inside_meta = minetest.get_meta(inside_pos)
		container_pos = minetest.string_to_pos(
			inside_meta:get_string("area_containers:container_pos"))
		relation_containers[idx] = container_pos
	end
	return container_pos
end

function area_containers.set_related_container(param1, param2, container_pos)
	local inside_pos = get_related_inside(param1, param2)
	local inside_meta = minetest.get_meta(inside_pos)
	inside_meta:set_string("area_containers:container_pos",
		container_pos and minetest.pos_to_string(container_pos) or "")
	relation_containers[get_index(param1, param2)] = container_pos
end