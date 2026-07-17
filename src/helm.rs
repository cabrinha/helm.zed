use std::fs;
use zed::LanguageServerId;
use zed_extension_api::{self as zed, serde_json, settings::LspSettings, Result};

struct HelmExtension {
    cached_binary_path: Option<String>,
}

impl HelmExtension {
    const HELM_LS: &'static str = "helm_ls";
    const HELM_LS_HYPHENATED: &'static str = "helm-ls";

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
            .which(Self::HELM_LS)
            .or_else(|| worktree.which(Self::HELM_LS_HYPHENATED))
        {
            self.cached_binary_path = Some(path.clone());
            return Ok(path);
        }

        // Resolve platform strings once — used for both the disk scan and the
        // asset/binary name construction below.
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

        // The asset filename used by helm-ls releases, e.g. "helm_ls_linux_amd64".
        let binary_name = format!("{binary_prefix}{os}_{arch}{extension}");

        // 3. Disk scan: look for a binary from a previous download.
        //    This is the offline fallback — if the network call below fails we
        //    can still return a working binary that was installed earlier.
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

        // 4. Try to reach GitHub for the latest release.
        //    If offline, fall back to whatever is already on disk (step 3).
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

        // 5. Already on the latest version — nothing to download.
        let version_dir = format!("{binary_prefix}{}", release.version);
        let binary_path = format!("{version_dir}/{binary_name}");

        if !fs::metadata(&binary_path).map_or(false, |stat| stat.is_file()) {
            // 6. Download the new release.
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

            // 7. Remove older version directories to keep the extension directory clean.
            let entries =
                fs::read_dir(".").map_err(|e| format!("failed to list working directory: {e}"))?;
            for entry in entries {
                let entry = entry.map_err(|e| format!("failed to read directory entry: {e}"))?;
                if entry.file_name().to_str() != Some(&version_dir) {
                    fs::remove_dir_all(entry.path()).ok();
                }
            }
        }

        self.cached_binary_path = Some(binary_path.clone());
        Ok(binary_path)
    }
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
        Ok(zed::Command {
            command: self.language_server_binary_path(language_server_id, worktree)?,
            args: vec!["serve".to_string()],
            env: Default::default(),
        })
    }

    fn language_server_workspace_configuration(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        let settings = LspSettings::for_worktree(Self::HELM_LS, worktree)
            .ok()
            .and_then(|lsp_settings| lsp_settings.settings.clone())
            .unwrap_or_default();
        Ok(Some(settings))
    }
}

zed_extension_api::register_extension!(HelmExtension);
