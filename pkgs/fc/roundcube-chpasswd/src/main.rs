#[macro_use]
extern crate clap;

use anyhow::{bail, ensure, Context, Result};
use clap::{app_from_crate, Arg};
use env_logger::{Builder, Env};
use fs2::FileExt;
use log::{error, info, warn};
use pwhash::sha256_crypt;
use std::fmt;
use std::fs::OpenOptions;
use std::io::{prelude::*, stdin, SeekFrom};
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct Cred<'a> {
    user: &'a str,
    pass: &'a str,
}

impl<'a> Cred<'a> {
    fn new(user: &'a str, pass: &'a str) -> Self {
        Cred { user, pass }
    }

    // Split colon-separated username:password pair
    fn from_str(line: &'a str) -> Result<Self> {
        let mut split = line.trim().splitn(2, ':');
        match (split.next(), split.next()) {
            (Some(user), Some(pass)) if !user.is_empty() => Ok(Cred::new(user, pass)),
            _ => bail!("expected format USERNAME:PASSWORD"),
        }
    }
}

impl fmt::Display for Cred<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}", self.user, self.pass)
    }
}

// Crypt password with SHA-256 and update appropriate line in `pwfile`. Fails if the user is
// not present exactly once in the file.
#[allow(deprecated)]
fn update(pwfile: &Path, new: Cred) -> Result<()> {
    let mut f = OpenOptions::new()
        .read(true)
        .write(true)
        .open(pwfile)
        .context("failed to open file")?;
    f.lock_exclusive().context("failed to acquire lock")?;
    info!("{}: updating password for '{}'", pwfile.display(), new.user);
    ensure!(
        new.pass.is_ascii(),
        "non-ASCII characters not allowed in password"
    );
    if new.pass.len() < 8 {
        warn!("password is only {} characters long", new.pass.len());
    }
    let mut old = String::with_capacity(f.metadata()?.len() as usize);
    f.read_to_string(&mut old)?;
    let new_cred = Cred::new(new.user, &sha256_crypt::hash(new.pass)?).to_string();
    let mut updated: Vec<&str> = Vec::new();
    let mut found = false;
    for line in old.lines() {
        let c = Cred::from_str(line)
            .with_context(|| format!("failed to parse passwd line '{}'", line))?;
        if c.user == new.user {
            if !found {
                updated.push(&new_cred);
                found = true;
            } else {
                warn!("duplicate entry for '{}'", new.user);
            }
        } else {
            updated.push(line);
        }
    }
    ensure!(found, "user '{}' not found", new.user);
    updated.sort();
    f.seek(SeekFrom::Start(0))?;
    f.set_len(0)?;
    writeln!(f, "{}", updated.join("\n"))?;
    Ok(())
}

fn run() -> Result<()> {
    let opt = app_from_crate!()
        .arg(
            Arg::with_name("pwfile")
                .value_name("PASSWD")
                .required(true)
                .help("Shared Dovecot/Roundcube password file"),
        )
        .after_help("A new username:password combination is expected on stdin (colon-separated).")
        .get_matches();
    let pwfile = opt.value_of_os("pwfile").unwrap();
    let mut line = String::with_capacity(160);
    let n = stdin().read_line(&mut line)?;
    ensure!(n > 0, "Unexpected empty input line");
    let cred = Cred::from_str(&line).context("unexpected input on stdin")?;
    Ok(update(&Path::new(&pwfile), cred)
        .with_context(|| format!("{}", pwfile.to_string_lossy()))?)
}

fn main() {
    Builder::from_env(Env::default().default_filter_or("info"))
        .format_timestamp(None)
        .init();
    if let Err(e) = run() {
        error!("{:#}", e);
        std::process::exit(2);
    }
}

#[cfg(test)]
mod test {
    use super::*;
    use regex::Regex;
    use std::fs;
    use tempfile::{tempdir, NamedTempFile};

    #[test]
    fn update_password() -> Result<()> {
        let tf = NamedTempFile::new()?;
        fs::write(tf.path(), "user1:$6$old$old\n")?;
        update(tf.path(), Cred::new("user1", "newpass"))?;
        let after = fs::read_to_string(tf.path())?;
        let re = Regex::new(r"^user1:\$5\$\S{16}\$\S{43}\n$")?;
        assert!(re.is_match(&after), format!("no match: {}", &after));
        Ok(())
    }

    #[test]
    fn update_should_preserve_order() -> Result<()> {
        let tf = NamedTempFile::new()?;
        fs::write(
            tf.path(),
            "c_u0:$5$old$old0\n\
             a_u1:$5$old$old1\n\
             d_u2:$5$old$old2\n\
             b_u3:$5$old$old3\n",
        )?;
        update(tf.path(), Cred::new("a_u1", "newpass"))?;
        let after = fs::read_to_string(tf.path())?;
        let re = Regex::new(r"^a_u1:\$5\$.*\nb_u3:\$5\$.*\nc_u0:\$5\$.*\nd_u2:\$5\$.*\n")?;
        assert!(re.is_match(&after), format!("no match: {}", &after));
        Ok(())
    }

    #[test]
    fn update_should_fail_if_no_user() -> Result<()> {
        let tf = NamedTempFile::new()?;
        fs::write(tf.path(), "user1:$6$old$old\n")?;
        let res = update(tf.path(), Cred::new("user2", "newpass"));
        assert!(res.is_err(), "Error expected: {:?}", res);
        Ok(())
    }

    #[test]
    fn deduplicate_user() -> Result<()> {
        let tf = NamedTempFile::new()?;
        fs::write(
            tf.path(),
            "user0:$5$old$old0\n\
             user1:$5$old$old1\n\
             user1:$5$old$old2\n\
             user2:$5$old$old3\n",
        )?;
        update(tf.path(), Cred::new("user1", "newpass"))?;
        let after = fs::read_to_string(tf.path())?;
        let re = Regex::new(r"^user0:\$5\$.*\nuser1:\$5\$.*\nuser2:\$5\$.*\n$")?;
        assert!(re.is_match(&after), format!("no match: {}", &after));
        Ok(())
    }

    #[test]
    fn update_should_not_create_file() -> Result<()> {
        let dir = tempdir()?;
        let res = update(&dir.path().join("passwd"), Cred::new("user1", "pass1"));
        assert!(res.is_err(), "{:?}", res);
        Ok(())
    }

    #[test]
    fn reject_non_ascii() -> Result<()> {
        let tf = NamedTempFile::new()?;
        fs::write(tf.path(), "user1:$6$old$old\n")?;
        let res = update(tf.path(), Cred::new("user1", "pässwörd"));
        assert!(res.is_err(), "Error expected: {:?}", res);
        Ok(())
    }

    #[test]
    fn split_should_expect_user_and_password() {
        assert!(Cred::from_str("").is_err(), "empty string");
        assert!(Cred::from_str("user").is_err(), "no colon");
        assert!(Cred::from_str(":").is_err(), "lone colon");
        assert!(Cred::from_str(":pass").is_err(), "empty user");
    }

    #[test]
    fn split_username_password() {
        assert_eq!(
            Cred::from_str("user1:pass2").unwrap(),
            Cred::new("user1", "pass2")
        );
        assert_eq!(Cred::from_str("user1:").unwrap(), Cred::new("user1", ""));
    }
}
