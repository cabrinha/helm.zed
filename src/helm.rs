use zed_extension_api::{self as zed, Result};

struct HelmExtension;

impl zed::Extension for HelmExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        _config: zed::LanguageServerConfig,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let path = worktree
            .which("helm_ls")
            .ok_or_else(|| "The LSP for helm 'helm-ls' is not installed".to_string())?;

        Ok(zed::Command {
            command: path,
            args: vec!["serve".to_string()],
            env: Default::default(),
        })
    }
}

zed::register_extension!(HelmExtension);
