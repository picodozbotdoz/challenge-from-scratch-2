import Lake
open Lake DSL

package «feedasm» {
  -- Lean core only: no dependencies.
}

lean_lib Feed where
  globs := #[.submodules `Feed]

@[default_target]
lean_exe «speccheck» {
  root := `Feed.Main
}

lean_exe «derive» {
  root := `Feed.Derive
}
