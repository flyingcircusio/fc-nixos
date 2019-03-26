use super::*;
use lazy_static::lazy_static;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::os::unix::fs::symlink;
use std::path::Path;
use tempdir::TempDir;

lazy_static! {
    static ref FIXTURES: &'static Path =
        Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/fixtures"));
    static ref RESULTS: CheckResults = {
        env::set_current_dir(*FIXTURES).unwrap();
        walk(".").unwrap()
    };
}

#[test]
fn should_check_json_files() {
    let res: HashMap<&Path, i32> = RESULTS
        .iter()
        .map(|(p, s)| (p.as_path(), s.code()))
        .collect();
    assert_eq!(
        res,
        [
            (Path::new("./empty.json"), 2),
            (Path::new("./missing.json"), 2),
            (Path::new("./nochecks.json"), 1),
            (Path::new("./ok.json"), 0),
            (Path::new("./syntaxerror.json"), 2),
        ]
        .iter()
        .cloned()
        .collect()
    )
}

#[test]
fn should_ignore_subdir() -> Fallible<()> {
    let td = TempDir::new("should_ignore_subdir")?;
    fs::create_dir(td.path().join("sub"))?;
    Ok(assert!(walk(td.path())?.is_empty()))
}

#[test]
fn should_consider_symlinks() -> Fallible<()> {
    let td = TempDir::new("should_consider_symlinks")?;
    symlink(FIXTURES.join("ok.json"), td.path().join("linked.json"))?;
    Ok(assert_eq!(walk(td.path())?.len(), 1))
}
