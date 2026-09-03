mod binary;

use std::fs;
use zed::LanguageServerId;
use zed_extension_api::{self as zed, serde_json, settings::LspSettings, Result};

use binary::{
    any_cached_binary, asset_name, binary_relpath, download_url, pinned_binary_if_present,
    should_remove_managed_dir, version_dir, HELM_LS, HELM_LS_GITHUB_REPO, HELM_LS_HYPHENATED,
    HELM_LS_VERSION,
};

struct HelmExtension {
    cached_binary_path: Option<String>,
}

impl HelmExtension {
    /// User settings for this language server live under a single key: the
    /// language server ID from extension.toml (`[language_servers.helm]`),
    /// i.e. `lsp.helm` in settings.json. This matches the convention in
    /// Zed's own extensions
    /// (`LspSettings::for_worktree(server_id.as_ref(), worktree)`).
    fn lsp_settings(
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> LspSettings {
        LspSettings::for_worktree(language_server_id.as_ref(), worktree).unwrap_or_default()
    }

    fn language_server_binary_path(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<String> {
        // 1. In-memory cache: fastest path, valid within a single Zed session.
        if let Some(path) = &self.cached_binary_path {
            if fs::metadata(path).map_or(false, |stat| stat.is_file()) {
                return Ok(path.clone());
            }
        }

        // 2. System-wide installation: respect an existing helm_ls or helm-ls on PATH.
        if let Some(path) = worktree
            .which(HELM_LS)
            .or_else(|| worktree.which(HELM_LS_HYPHENATED))
        {
            self.cached_binary_path = Some(path.clone());
            return Ok(path);
        }

        let (os, arch, exe_suffix) = platform_triple();
        let exists = |path: &str| fs::metadata(path).map_or(false, |stat| stat.is_file());

        // 3. Pinned binary already downloaded. Skip GitHub entirely so a cold
        //    Zed start does not call latest_github_release / the releases API.
        if let Some(path) = pinned_binary_if_present(exists, HELM_LS_VERSION, os, arch, exe_suffix)
        {
            self.cached_binary_path = Some(path.clone());
            return Ok(path);
        }

        // 4. Download the pinned release. Fall back to any older cached binary
        //    if we are offline or GitHub is unreachable.
        match self.download_pinned(language_server_id, os, arch, exe_suffix) {
            Ok(path) => {
                self.cached_binary_path = Some(path.clone());
                Ok(path)
            }
            Err(err) => {
                let dirs = list_dir_names(".");
                let names: Vec<&str> = dirs.iter().map(|s| s.as_str()).collect();
                if let Some(path) = any_cached_binary(&names, exists, os, arch, exe_suffix) {
                    self.cached_binary_path = Some(path.clone());
                    return Ok(path);
                }
                Err(err)
            }
        }
    }

    fn download_pinned(
        &self,
        language_server_id: &LanguageServerId,
        os: &str,
        arch: &str,
        exe_suffix: &str,
    ) -> Result<String> {
        zed::set_language_server_installation_status(
            language_server_id,
            &zed::LanguageServerInstallationStatus::CheckingForUpdate,
        );

        let wanted = asset_name(os, arch, exe_suffix);
        // Prefer the tagged release asset URL, but do not require the GitHub API
        // to succeed: the download URL is deterministic for a pinned tag.
        let url = zed::github_release_by_tag_name(HELM_LS_GITHUB_REPO, HELM_LS_VERSION)
            .ok()
            .and_then(|release| {
                release
                    .assets
                    .iter()
                    .find(|asset| asset.name == wanted)
                    .map(|asset| asset.download_url.clone())
            })
            .unwrap_or_else(|| download_url(HELM_LS_VERSION, os, arch, exe_suffix));

        let version_dir = version_dir(HELM_LS_VERSION);
        let binary_path = binary_relpath(HELM_LS_VERSION, os, arch, exe_suffix);

        fs::create_dir_all(&version_dir)
            .map_err(|err| format!("failed to create directory '{version_dir}': {err}"))?;

        zed::set_language_server_installation_status(
            language_server_id,
            &zed::LanguageServerInstallationStatus::Downloading,
        );

        zed::download_file(&url, &binary_path, zed::DownloadedFileType::Uncompressed)
            .map_err(|e| format!("failed to download file: {e}"))?;

        zed::make_file_executable(&binary_path)?;

        // Remove older helm-ls version dirs only. The previous implementation
        // called remove_dir_all on every sibling, which would delete languages/
        // and grammars/ after the first download.
        let entries =
            fs::read_dir(".").map_err(|e| format!("failed to list working directory: {e}"))?;
        for entry in entries {
            let entry = entry.map_err(|e| format!("failed to read directory entry: {e}"))?;
            let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
                continue;
            };
            if should_remove_managed_dir(&name, &version_dir) {
                fs::remove_dir_all(entry.path()).ok();
            }
        }

        Ok(binary_path)
    }

    fn helm_ls_configuration(
        &self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> serde_json::Value {
        // helm-ls requests `workspace/configuration` with section `"helm-ls"`,
        // so nest the user's flat `lsp.helm.settings` object under that key.
        // With a single known settings key there is exactly one shape to
        // handle, no unwrapping/guessing.
        let user_settings = Self::lsp_settings(language_server_id, worktree)
            .settings
            .unwrap_or_else(|| serde_json::json!({}));
        inject_yamlls_path(
            wrap_helm_ls_settings(user_settings),
            yamlls_path(worktree),
        )
    }
}

fn platform_triple() -> (&'static str, &'static str, &'static str) {
    let (platform, arch) = zed::current_platform();
    let os = match platform {
        zed::Os::Mac => "darwin",
        zed::Os::Linux => "linux",
        zed::Os::Windows => "windows",
    };
    let arch = match arch {
        zed::Architecture::Aarch64 => "arm64",
        zed::Architecture::X86 => "x86",
        zed::Architecture::X8664 => "amd64",
    };
    let exe_suffix = match platform {
        zed::Os::Mac | zed::Os::Linux => "",
        zed::Os::Windows => ".exe",
    };
    (os, arch, exe_suffix)
}

fn list_dir_names(path: &str) -> Vec<String> {
    fs::read_dir(path)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok())
        .filter_map(|e| e.file_name().into_string().ok())
        .collect()
}

/// Nest the flat user settings object under helm-ls's config section.
///
/// helm-ls asks for section `"helm-ls"` and unmarshals that into its config,
/// so `lsp.helm.settings = { "yamlls": ... }` must be sent as
/// `{ "helm-ls": { "yamlls": ... } }`.
fn wrap_helm_ls_settings(user_settings: serde_json::Value) -> serde_json::Value {
    serde_json::json!({ "helm-ls": user_settings })
}

/// Absolute path of a yaml-language-server on PATH, if one is installed.
///
/// helm-ls shells out to yaml-language-server for Kubernetes schema
/// validation. Its config knob is `yamlls.path`, also settable via the
/// `YAMLLS_PATH` env var, and its default executable is
/// `yaml-language-server` when neither is set. Resolving the absolute path
/// here avoids PATH lookup differences in Zed's spawned environment; an
/// explicit user `yamlls.path` still wins via `or_insert` below.
fn yamlls_path(worktree: &zed::Worktree) -> Option<String> {
    worktree.which("yaml-language-server")
}

fn inject_yamlls_path(
    mut settings: serde_json::Value,
    yamlls_path: Option<String>,
) -> serde_json::Value {
    let Some(path) = yamlls_path else {
        return settings;
    };
    let Some(root) = settings.as_object_mut() else {
        return settings;
    };
    let Some(helm_ls) = root.get_mut("helm-ls").and_then(|v| v.as_object_mut()) else {
        return settings;
    };
    let yamlls = helm_ls
        .entry("yamlls")
        .or_insert_with(|| serde_json::json!({}));
    if let Some(yamlls) = yamlls.as_object_mut() {
        yamlls.entry("path").or_insert(serde_json::json!(path));
    }
    settings
}

impl zed::Extension for HelmExtension {
    fn new() -> Self {
        Self {
            cached_binary_path: None,
        }
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let lsp_settings = Self::lsp_settings(language_server_id, worktree);
        let binary = lsp_settings.binary;

        let command = if let Some(path) = binary.as_ref().and_then(|b| b.path.clone()) {
            if !path.is_empty() {
                path
            } else {
                self.language_server_binary_path(language_server_id, worktree)?
            }
        } else {
            self.language_server_binary_path(language_server_id, worktree)?
        };

        let args = binary
            .as_ref()
            .and_then(|b| b.arguments.clone())
            .unwrap_or_else(|| vec!["serve".to_string()]);

        let mut env: std::collections::HashMap<String, String> =
            binary.and_then(|b| b.env).unwrap_or_default();

        if let Some(yamlls) = yamlls_path(worktree) {
            env.entry("YAMLLS_PATH".to_string()).or_insert(yamlls);
        }

        Ok(zed::Command {
            command,
            args,
            env: env.into_iter().collect(),
        })
    }

    fn language_server_initialization_options(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        Ok(Some(self.helm_ls_configuration(language_server_id, worktree)))
    }

    fn language_server_workspace_configuration(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        Ok(Some(self.helm_ls_configuration(language_server_id, worktree)))
    }
}

zed_extension_api::register_extension!(HelmExtension);

#[cfg(test)]
mod tests {
    use super::{inject_yamlls_path, wrap_helm_ls_settings};
    use zed_extension_api::serde_json::{json, Value};

    #[test]
    fn wraps_flat_user_settings_under_helm_ls_section() {
        let input = json!({ "yamlls": { "enabled": false } });
        assert_eq!(
            wrap_helm_ls_settings(input),
            json!({
                "helm-ls": { "yamlls": { "enabled": false } }
            })
        );
    }

    #[test]
    fn injects_yamlls_path_when_missing() {
        let settings = wrap_helm_ls_settings(json!({ "yamlls": { "enabled": true } }));
        let with_path = inject_yamlls_path(settings, Some("/usr/bin/yaml-language-server".into()));
        assert_eq!(
            with_path.pointer("/helm-ls/yamlls/path"),
            Some(&Value::String("/usr/bin/yaml-language-server".into()))
        );
        assert_eq!(
            with_path.pointer("/helm-ls/yamlls/enabled"),
            Some(&Value::Bool(true))
        );
    }

    #[test]
    fn does_not_override_explicit_yamlls_path() {
        let settings = wrap_helm_ls_settings(json!({
            "yamlls": { "path": "/custom/yamlls" }
        }));
        let with_path = inject_yamlls_path(settings, Some("/usr/bin/yaml-language-server".into()));
        assert_eq!(
            with_path.pointer("/helm-ls/yamlls/path"),
            Some(&Value::String("/custom/yamlls".into()))
        );
    }
}
