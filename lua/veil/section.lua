local utils = require("veil.utils")

local Rendered = {
	text = {},
	nlines = 0,
	longest = 0,
	virt = true,
	hl = "Normal",
	on_interact = nil,
	super = nil,
}

function Rendered:pad(width)
	local text = vim.deepcopy(self.text)
	local padding = 0
	if self.longest < width and self.longest > 0 then
		padding = math.ceil((width - self.longest) / 2)
	end
	for lno, line in ipairs(text) do
		text[lno] = string.rep(" ", padding) .. line
	end
	return setmetatable({
		text = text,
	}, {
		__index = self,
	})
end

function Rendered:new(opts)
	local new = vim.tbl_deep_extend("keep", opts or {}, self)
	return new
end

---@alias Highlight { fg: string|nil, bg: string|nil }
---@class Section
---@field interactive boolean Whether or not the section is interactive.
---@field hl string | Highlight | fun(self: Section):Highlight Highlight group to use for the section.
---@field focused_hl string | Highlight | fun(self: Section):Highlight HL for focused interactive section
---@field contents string[]|string|fun(self:Section):string[] The line or lines to be displayed
local Section = {
	---@type table<string, any>
	state = {},
	interactive = false,
	hl = "Normal",
	focused_hl = "Visual",
}

---@type fun(self: Section) Called when <CR> is entered with the cursor over a line in this section

function Section:on_interact() end

---@type fun(self: Section) Called once, when the component is initialized
function Section:init() end

---@type fun(self: Section):string[]
function Section:contents()
	return { "configure your veil!" }
end

---@alias SectionOpts Section
---@type fun(opts: table):Section
function Section:new(opts)
	local new = vim.tbl_deep_extend("force", self, opts)

	local mt = {
		__index = new.state,
		__newindex = function(state, k, v)
			-- Reserved names
			if k == "interactive" or k == "contents" then
				error("Section." .. k .. " cannot be updated after initialization", 2)
			else
				rawset(state, k, v)
			end
		end,
	}

	-- Generate random id for section hlgroup
	local sid = math.floor(math.random() * 100)
	local hl_id = "VeilSection" .. sid
	local focused_hl_id = "VeilSection" .. sid .. "F"

	local instance = {}

	-- Build the section and render function
	mt.__index.contents = new.contents
	mt.__index.interactive = new.interactive
	mt.__index.on_interact = new.on_interact
	mt.__index.hl = hl_id
	mt.__index.hl_val = new.hl
	mt.__index.focused_hl = focused_hl_id
	mt.__index.focused_hl_val = new.focused_hl
	---@type fun(tbl:Section):Rendered
	mt.__index.render = function(tbl)
		-- Create the new hlgroup
		local function eval(hl)
			if type(hl) == "function" then
				return hl(tbl)
			elseif type(hl) == "string" then
				return {
					fg = vim.fn.synIDattr(vim.fn.hlID(hl), "fg"),
					bg = vim.fn.synIDattr(vim.fn.hlID(hl), "bg"),
					bold = vim.fn.synIDattr(vim.fn.hlID(hl), "bold") == 1,
					italic = vim.fn.synIDattr(vim.fn.hlID(hl), "italic") == 1,
					underline = vim.fn.synIDattr(vim.fn.hlID(hl), "underline") == 1,
				}
			else
				return hl
			end
		end

		local veil = require("veil")
		if not veil.ns then
			veil.ns = vim.api.nvim_create_namespace("veil")
		end
		vim.api.nvim_set_hl(veil.ns, tbl.hl, eval(tbl.hl_val))
		vim.api.nvim_set_hl(veil.ns, tbl.focused_hl, eval(tbl.focused_hl_val))

		local contents = nil
		if type(tbl.contents) == "function" then
			contents = tbl:contents()
		elseif type(tbl.contents) == "table" then
			contents = tbl.contents
		elseif type(tbl.contents) == "string" then
			contents = { tbl.contents }
		else
			vim.api.nvim_err_writeln("Section.contents must be a function, string[], or string")
		end

		return Rendered:new({
			text = contents,
			nlines = #contents,
			longest = utils.longest_line(contents),
			virt = not tbl.interactive,
			hl = tbl.hl,
			focused_hl = tbl.focused_hl_val,
			on_interact = new.on_interact ~= nil and function(relno, col)
				instance:on_interact(relno, col)
			end or nil,
		})
	end

	return setmetatable(instance, mt)
end

return Section
