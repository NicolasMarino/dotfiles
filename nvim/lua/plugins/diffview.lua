-- Plugin: diffview.nvim
-- URL: https://github.com/sindrets/diffview.nvim
-- Description: Full-repo diff review — a file panel on the left listing every
-- changed file, a side-by-side diff on the right. This is the "see the files
-- and step into each one" view that LazyVim's pickers do not cover: <leader>gs
-- lists changed files but opens them one at a time, without a persistent panel.
--
-- Loaded on the commands only, so it costs nothing at startup.
return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
  opts = {
    enhanced_diff_hl = true,
    view = {
      -- merge_tool keeps the 3-way layout during conflicts; the default
      -- diff2_horizontal is the side-by-side review view.
      default = { layout = "diff2_horizontal" },
      merge_tool = { layout = "diff3_horizontal" },
    },
    file_panel = {
      listing_style = "tree",
      win_config = { width = 35 },
    },
  },
  -- Deliberately parked on <leader>gv: LazyVim already owns gs/gd/gl/gf/gb and
  -- gitsigns owns the whole <leader>gh prefix for hunk actions, so anything
  -- there would shadow an existing binding.
  keys = {
    { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Diffview: working tree" },
    { "<leader>gV", "<cmd>DiffviewOpen origin/HEAD...HEAD<cr>", desc = "Diffview: branch vs origin" },
    { "<leader>gr", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: repo history" },
    { "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
  },
}
