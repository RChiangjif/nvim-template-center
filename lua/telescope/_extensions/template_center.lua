-- `:Telescope template_center`
local ok, telescope = pcall(require, "telescope")
if not ok then
  error("the template_center extension requires telescope.nvim")
end

return telescope.register_extension({
  exports = {
    template_center = function(opts)
      require("template-center.picker").find(opts)
    end,
  },
})
