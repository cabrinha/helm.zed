use zed_extension_api::{self as zed, serde_json, settings::LspSettings, LanguageServerId, Result};

struct HelmExtension;

const HELM_LS: &str = "helm_ls";

impl zed::Extension for HelmExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let path = worktree
            .which(HELM_LS)
            .ok_or_else(|| "The LSP for helm 'helm-ls' is not installed".to_string())?;

        Ok(zed::Command {
            command: path,
            args: vec!["serve".to_string()],
            env: Default::default(),
        })
    }

    fn language_server_workspace_configuration(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        let settings = LspSettings::for_worktree(HELM_LS, worktree)
            .ok()
            .and_then(|lsp_settings| lsp_settings.settings.clone())
            .unwrap_or_default();
        Ok(Some(settings))
    }
}

zed::register_extension!(HelmExtension);
