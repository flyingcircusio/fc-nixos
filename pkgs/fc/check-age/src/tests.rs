use super::*;

use nix::sys::stat;
use nix::sys::time::{TimeVal, TimeValLike};
use std::fs;
use std::os::unix::fs::{symlink, PermissionsExt};
use tempfile::TempDir;

struct Setup {
    dir: TempDir,
}

impl Setup {
    fn path<P: AsRef<Path>>(&self, local: P) -> String {
        self.dir.path().join(local).to_string_lossy().to_string()
    }
}

fn setup<'a, I>(symlinks: I) -> Result<Setup>
where
    I: IntoIterator,
    I::Item: Into<&'a (&'a str, &'a str)>,
{
    let dir = TempDir::new()?;
    for item in symlinks {
        let (localname, age) = item.into();
        let full = dir.path().join(localname);
        symlink("/no/such/file", &full)?;
        let tv = TimeVal::seconds(
            (SystemTime::now() - *age.parse::<HDur>()?)
                .duration_since(SystemTime::UNIX_EPOCH)?
                .as_secs() as i64,
        );
        stat::lutimes(&full, &tv, &tv)?;
    }
    Ok(Setup { dir })
}

#[test]
fn no_threshold() {
    let s = setup(&[("link1", "30s")]).unwrap();
    let mut c = Check::new(Opt::from_iter(&["prog", &s.path("link1")]));
    assert_eq!(0, c.run().unwrap());
    assert_eq!(
        format!("OK: no outdated items | {}=30s;;;0", s.path("link1")),
        c.to_string()
    );
}

#[test]
fn warning_1() {
    let s = setup(&[("l1", "30s"), ("l2", "40s")]).unwrap();
    let mut c = Check::new(Opt::from_iter(&[
        "prog",
        "-w 35s",
        &s.path("l1"),
        &s.path("l2"),
    ]));
    assert_eq!(1, c.run().unwrap());
    assert_eq!(
        format!(
            "WARNING: older than 35s: {} | {}=30s;35;;0 {}=40s;35;;0",
            s.path("l2"),
            s.path("l1"),
            s.path("l2"),
        ),
        c.to_string()
    );
}

#[test]
fn critical_2() {
    let s = setup(&[("l1", "30s"), ("l2", "40s")]).unwrap();
    let mut c = Check::new(Opt::from_iter(&[
        "prog",
        "-c 10s",
        &s.path("l1"),
        &s.path("l2"),
    ]));
    assert_eq!(2, c.run().unwrap());
    assert_eq!(
        format!(
            "CRITICAL: older than 10s: {}, {} | {}=30s;;10;0 {}=40s;;10;0",
            s.path("l1"),
            s.path("l2"),
            s.path("l1"),
            s.path("l2"),
        ),
        c.to_string()
    );
}

#[test]
fn warning_1_critical_1() {
    let s = setup(&[("l1", "30s"), ("l2", "40s")]).unwrap();
    let mut c = Check::new(Opt::from_iter(&[
        "prog",
        "-w 25s",
        "-c 35s",
        &s.path("l1"),
        &s.path("l2"),
    ]));
    assert_eq!(2, c.run().unwrap());
    assert_eq!(
        format!(
            "CRITICAL: older than 35s: {} - older than 25s: {} | {}=30s;25;35;0 {}=40s;25;35;0",
            s.path("l2"),
            s.path("l1"),
            s.path("l1"),
            s.path("l2"),
        ),
        c.to_string()
    );
}

#[test]
fn ignore_missing_file() {
    // should be critical
    let mut c = Check::new(Opt::from_iter(&["prog", "/no/such/file"]));
    assert_eq!(2, c.run().unwrap());
    assert_eq!("CRITICAL: missing: /no/such/file |", c.to_string());
    // should be OK with '-m'
    let mut c = Check::new(Opt::from_iter(&["prog", "-m", "/no/such/file"]));
    assert_eq!(0, c.run().unwrap());
}

#[test]
fn human_format_in_msg_but_not_in_perfdata() {
    let s = setup(&[("l", "1day 10s")]).unwrap();
    let mut c = Check::new(Opt::from_iter(&["prog", "-c", "1day5s", &s.path("l")]));
    assert_eq!(2, c.run().unwrap());
    assert_eq!(
        format!(
            "CRITICAL: older than 1day 5s: {} | {}=86410s;;86405;0",
            s.path("l"),
            s.path("l"),
        ),
        c.to_string()
    );
}

#[test]
fn read_error() -> Result<()> {
    let td = TempDir::new()?;
    let dir = td.path().join("dir");
    fs::create_dir(&dir)?;
    let file = dir.join("file");
    fs::File::create(&file)?;
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o000))?;
    let mut c = Check::new(Opt::from_iter(&["prog", &string(&file)]));
    assert_eq!(
        format!("{}: Permission denied (os error 13)", file.display()),
        format!("{:#}", c.run().unwrap_err())
    );
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o755))?; // else it won't be deleted
    Ok(())
}

#[test]
fn no_file() {
    let mut c = Check::new(Opt::from_iter(&["prog"]));
    assert_eq!(
        "No file/symlink to check",
        format!("{:#}", c.run().unwrap_err())
    );
}
