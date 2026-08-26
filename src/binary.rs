//! Path and version helpers for the helm-ls binary this extension installs.
//!
//! Kept free of `zed_extension_api` so the cache/pin rules can be unit-tested
//! on the host without compiling the WASM extension.

pub const HELM_LS: &str = "helm_ls";
pub const HELM_LS_HYPHENATED: &str = "helm-ls";
/// Pinned helm-ls GitHub release tag. Bump this (and re-test) to pick up a new server.
pub const HELM_LS_VERSION: &str = "v0.5.4";
pub const HELM_LS_GITHUB_REPO: &str = "mrjosh/helm-ls";

const VERSION_DIR_PREFIX: &str = "helm_ls_";

pub fn version_dir(version: &str) -> String {
    format!("{VERSION_DIR_PREFIX}{version}")
}

pub fn asset_name(os: &str, arch: &str, exe_suffix: &str) -> String {
    format!("{HELM_LS}_{os}_{arch}{exe_suffix}")
}

pub fn binary_relpath(version: &str, os: &str, arch: &str, exe_suffix: &str) -> String {
    format!(
        "{}/{}",
        version_dir(version),
        asset_name(os, arch, exe_suffix)
    )
}

pub fn download_url(version: &str, os: &str, arch: &str, exe_suffix: &str) -> String {
    format!(
        "https://github.com/{HELM_LS_GITHUB_REPO}/releases/download/{version}/{}",
        asset_name(os, arch, exe_suffix)
    )
}

/// Directories this extension creates for downloaded helm-ls builds.
pub fn is_managed_version_dir(name: &str) -> bool {
    name.starts_with(VERSION_DIR_PREFIX)
}

/// Only previously downloaded helm-ls version dirs should be removed.
/// Never touch `languages/`, `grammars/`, or other extension files.
pub fn should_remove_managed_dir(name: &str, keep_version_dir: &str) -> bool {
    is_managed_version_dir(name) && name != keep_version_dir
}

/// Use the pinned binary when it is already on disk. No GitHub call needed.
pub fn pinned_binary_if_present(
    exists: impl Fn(&str) -> bool,
    version: &str,
    os: &str,
    arch: &str,
    exe_suffix: &str,
) -> Option<String> {
    let path = binary_relpath(version, os, arch, exe_suffix);
    exists(&path).then_some(path)
}

/// Offline fallback: any previously downloaded helm-ls binary for this target.
/// Prefers the pinned version if both exist.
pub fn any_cached_binary(
    dir_names: &[&str],
    exists: impl Fn(&str) -> bool,
    os: &str,
    arch: &str,
    exe_suffix: &str,
) -> Option<String> {
    let asset = asset_name(os, arch, exe_suffix);
    let pinned = version_dir(HELM_LS_VERSION);

    if dir_names.contains(&pinned.as_str()) {
        let path = format!("{pinned}/{asset}");
        if exists(&path) {
            return Some(path);
        }
    }

    for name in dir_names {
        if !is_managed_version_dir(name) {
            continue;
        }
        let path = format!("{name}/{asset}");
        if exists(&path) {
            return Some(path);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pins_a_real_helm_ls_tag() {
        assert!(HELM_LS_VERSION.starts_with('v'));
        assert_eq!(HELM_LS_VERSION, "v0.5.4");
    }

    #[test]
    fn linux_amd64_paths_match_helm_ls_release_assets() {
        assert_eq!(asset_name("linux", "amd64", ""), "helm_ls_linux_amd64");
        assert_eq!(version_dir("v0.5.4"), "helm_ls_v0.5.4");
        assert_eq!(
            binary_relpath("v0.5.4", "linux", "amd64", ""),
            "helm_ls_v0.5.4/helm_ls_linux_amd64"
        );
        assert_eq!(
            download_url("v0.5.4", "linux", "amd64", ""),
            "https://github.com/mrjosh/helm-ls/releases/download/v0.5.4/helm_ls_linux_amd64"
        );
    }

    #[test]
    fn windows_asset_keeps_exe_suffix() {
        assert_eq!(
            asset_name("windows", "amd64", ".exe"),
            "helm_ls_windows_amd64.exe"
        );
    }

    #[test]
    fn darwin_arm64_asset_name() {
        assert_eq!(asset_name("darwin", "arm64", ""), "helm_ls_darwin_arm64");
    }

    #[test]
    fn cleanup_only_removes_other_helm_ls_version_dirs() {
        let keep = "helm_ls_v0.5.4";
        assert!(should_remove_managed_dir("helm_ls_v0.5.3", keep));
        assert!(!should_remove_managed_dir(keep, keep));
        assert!(!should_remove_managed_dir("languages", keep));
        assert!(!should_remove_managed_dir("grammars", keep));
        assert!(!should_remove_managed_dir("src", keep));
        assert!(!should_remove_managed_dir("extension.wasm", keep));
        assert!(!should_remove_managed_dir("target", keep));
    }

    #[test]
    fn skips_github_when_pinned_binary_is_on_disk() {
        let exists = |path: &str| path == "helm_ls_v0.5.4/helm_ls_linux_amd64";
        assert_eq!(
            pinned_binary_if_present(exists, "v0.5.4", "linux", "amd64", ""),
            Some("helm_ls_v0.5.4/helm_ls_linux_amd64".into())
        );
        assert_eq!(
            pinned_binary_if_present(|_| false, "v0.5.4", "linux", "amd64", ""),
            None
        );
    }

    #[test]
    fn cached_lookup_prefers_pinned_over_older_builds() {
        let dirs = ["languages", "helm_ls_v0.5.3", "helm_ls_v0.5.4", "grammars"];
        let exists = |path: &str| {
            path == "helm_ls_v0.5.3/helm_ls_linux_amd64"
                || path == "helm_ls_v0.5.4/helm_ls_linux_amd64"
        };
        assert_eq!(
            any_cached_binary(&dirs, exists, "linux", "amd64", ""),
            Some("helm_ls_v0.5.4/helm_ls_linux_amd64".into())
        );
    }

    #[test]
    fn cached_lookup_falls_back_to_an_older_build() {
        let dirs = ["helm_ls_v0.5.3", "languages"];
        let exists = |path: &str| path == "helm_ls_v0.5.3/helm_ls_linux_amd64";
        assert_eq!(
            any_cached_binary(&dirs, exists, "linux", "amd64", ""),
            Some("helm_ls_v0.5.3/helm_ls_linux_amd64".into())
        );
    }

    #[test]
    fn cached_lookup_ignores_unrelated_directories() {
        let dirs = ["languages", "grammars", "target"];
        assert_eq!(
            any_cached_binary(&dirs, |_| true, "linux", "amd64", ""),
            None
        );
    }
}
