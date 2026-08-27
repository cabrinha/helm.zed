use std::fs;
use zed::LanguageServerId;
use zed_extension_api::{self as zed, serde_json, settings::LspSettings, Result};

struct HelmExtension {
    cached_binary_path: Option<String>,
}

impl HelmExtension {
    const HELM_LS: &'static str = "helm_ls";
    const HELM_LS_HYPHENATED: &'static str = "helm-ls";
    /// Keys users actually put under `lsp` in settings.json. The language
    /// server id in extension.toml is `helm`, the display name is `helm_ls`,
    /// and helm-ls's own config section is `helm-ls`.
    const LSP_SETTING_KEYS: &'static [&'static str] = &["helm_ls", "helm-ls", "helm"];

    fn lsp_settings(worktree: &zed::Worktree) -> LspSettings {
        for key in Self::LSP_SETTING_KEYS {
            if let Ok(settings) = LspSettings::for_worktree(key, worktree) {
                if settings.binary.is_some()
                    || settings.settings.is_some()
                    || settings.initialization_options.is_some()
                {
                    return settings;
                }
            }
        }
        LspSettings::for_worktree(Self::HELM_LS, worktree).unwrap_or_default()
    }

    fn language_server_binary_path(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<String> {
        if let Some(path) = &self.cached_binary_path {
            if fs::metadata(path).map_or(false, |stat| stat.is_file()) {
                return Ok(path.clone());
            }
        }

        if let Some(path) = worktree
            .which(Self::HELM_LS)
            .or_else(|| worktree.which(Self::HELM_LS_HYPHENATED))
        {
            self.cached_binary_path = Some(path.clone());
            return Ok(path);
        }

        let (platform, arch) = zed::current_platform();
        let binary_prefix = format!("{}_", Self::HELM_LS);

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
        let extension = match platform {
            zed::Os::Mac | zed::Os::Linux => "",
            zed::Os::Windows => ".exe",
        };

        let binary_name = format!("{binary_prefix}{os}_{arch}{extension}");

        let installed_binary_path = fs::read_dir(".").ok().and_then(|entries| {
            entries
                .filter_map(|e| e.ok())
                .filter(|e| {
                    e.file_name()
                        .to_str()
                        .map_or(false, |n| n.starts_with(&binary_prefix))
                })
                .filter_map(|dir| {
                    let dir_name = dir.file_name();
                    let path = format!("{}/{binary_name}", dir_name.to_str()?);
                    if fs::metadata(&path).map_or(false, |s| s.is_file()) {
                        Some(path)
                    } else {
                        None
                    }
                })
                .next()
        });

        zed::set_language_server_installation_status(
            language_server_id,
            &zed::LanguageServerInstallationStatus::CheckingForUpdate,
        );
        let release = match zed::latest_github_release(
            "mrjosh/helm-ls",
            zed::GithubReleaseOptions {
                require_assets: true,
                pre_release: false,
            },
        ) {
            Ok(release) => release,
            Err(_) => {
                if let Some(path) = installed_binary_path {
                    self.cached_binary_path = Some(path.clone());
                    return Ok(path);
                }
                return Err(format!(
                    "{} is not installed and cannot be downloaded without an internet connection",
                    Self::HELM_LS
                )
                .into());
            }
        };

        let version_dir = format!("{binary_prefix}{}", release.version);
        let binary_path = format!("{version_dir}/{binary_name}");

        if !fs::metadata(&binary_path).map_or(false, |stat| stat.is_file()) {
            let asset = release
                .assets
                .iter()
                .find(|asset| asset.name == binary_name)
                .ok_or_else(|| format!("no asset found matching {:?}", binary_name))?;

            fs::create_dir_all(&version_dir)
                .map_err(|err| format!("failed to create directory '{version_dir}': {err}"))?;

            zed::set_language_server_installation_status(
                language_server_id,
                &zed::LanguageServerInstallationStatus::Downloading,
            );

            zed::download_file(
                &asset.download_url,
                &binary_path,
                zed::DownloadedFileType::Uncompressed,
            )
            .map_err(|e| format!("failed to download file: {e}"))?;

            zed::make_file_executable(&binary_path)?;

            let entries =
                fs::read_dir(".").map_err(|e| format!("failed to list working directory: {e}"))?;
            for entry in entries {
                let entry = entry.map_err(|e| format!("failed to read directory entry: {e}"))?;
                let name = entry.file_name();
                let Some(name) = name.to_str() else {
                    continue;
                };
                if name.starts_with(&binary_prefix) && name != version_dir {
                    fs::remove_dir_all(entry.path()).ok();
                }
            }
        }

        self.cached_binary_path = Some(binary_path.clone());
        Ok(binary_path)
    }
}

/// Pull the inner helm-ls config out of whatever shape the user wrote.
///
/// Zed answers helm-ls's `workspace/configuration` request for section
/// `"helm-ls"` with `returned_json["helm-ls"]`. If we pass the README shape
/// through unchanged that works. If the user put `yamlls` at the top of
/// `lsp.helm_ls.settings`, Zed would return null and helm-ls would keep
/// defaults, including yamlls.enabled=true.
fn unwrap_helm_ls_section(settings: serde_json::Value) -> serde_json::Value {
    match settings {
        serde_json::Value::Object(mut map) => {
            if let Some(inner) = map.remove("helm-ls").or_else(|| map.remove("helm_ls")) {
                inner
            } else {
                serde_json::Value::Object(map)
            }
        }
        other => other,
    }
}

fn wrap_helm_ls_settings(user_settings: serde_json::Value) -> serde_json::Value {
    serde_json::json!({ "helm-ls": unwrap_helm_ls_section(user_settings) })
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
        let lsp_settings = Self::lsp_settings(worktree);
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

        if let Some(yamlls) = worktree
            .which("yaml-language-server")
            .or_else(|| worktree.which("yaml-language-server.js"))
        {
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
        _language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        Ok(Some(self.helm_ls_configuration(worktree)))
    }

    fn language_server_workspace_configuration(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        Ok(Some(self.helm_ls_configuration(worktree)))
    }
}

impl HelmExtension {
    fn helm_ls_configuration(&self, worktree: &zed::Worktree) -> serde_json::Value {
        let user_settings = Self::lsp_settings(worktree)
            .settings
            .unwrap_or_else(|| serde_json::json!({}));
        let yamlls_path = worktree
            .which("yaml-language-server")
            .or_else(|| worktree.which("yaml-language-server.js"));
        inject_yamlls_path(wrap_helm_ls_settings(user_settings), yamlls_path)
    }
}

zed_extension_api::register_extension!(HelmExtension);

#[cfg(test)]
mod tests {
    use super::{inject_yamlls_path, unwrap_helm_ls_section, wrap_helm_ls_settings};
    use zed_extension_api::serde_json::{json, Value};

    #[test]
    fn unwraps_readme_nested_helm_ls_key() {
        let input = json!({
            "helm-ls": {
                "yamlls": { "enabled": false }
            }
        });
        assert_eq!(
            unwrap_helm_ls_section(input),
            json!({ "yamlls": { "enabled": false } })
        );
    }

    #[test]
    fn unwraps_underscore_key() {
        let input = json!({
            "helm_ls": {
                "logLevel": "debug"
            }
        });
        assert_eq!(
            unwrap_helm_ls_section(input),
            json!({ "logLevel": "debug" })
        );
    }

    #[test]
    fn passes_through_flat_yamlls_settings() {
        let input = json!({ "yamlls": { "enabled": false } });
        assert_eq!(
            unwrap_helm_ls_section(input.clone()),
            json!({ "yamlls": { "enabled": false } })
        );
        assert_eq!(
            wrap_helm_ls_settings(input),
            json!({
                "helm-ls": { "yamlls": { "enabled": false } }
            })
        );
    }

    #[test]
    fn wrap_is_idempotent_for_readme_shape() {
        let input = json!({
            "helm-ls": {
                "yamlls": { "enabled": false }
            }
        });
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
