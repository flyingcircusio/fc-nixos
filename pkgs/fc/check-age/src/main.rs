use anyhow::{ensure, Context, Result};
use humantime::Duration as HDur;
use std::fmt;
use std::fs::symlink_metadata;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::exit;
use std::time::{Duration, SystemTime};
use structopt::StructOpt;

#[cfg(test)]
mod tests;

fn string(p: &Path) -> String {
    p.to_string_lossy().to_string()
}

#[derive(Debug)]
struct Check {
    opt: Opt,
    ages: Vec<Option<Duration>>,
    crit: Vec<String>,
    warn: Vec<String>,
    miss: Vec<String>,
}

impl Check {
    fn new(opt: Opt) -> Self {
        let cap = opt.paths.len();
        Self {
            opt,
            ages: Vec::with_capacity(cap),
            crit: Vec::with_capacity(cap),
            warn: Vec::with_capacity(cap),
            miss: Vec::with_capacity(cap),
        }
    }

    fn age(&self, path: &Path) -> Result<Option<Duration>> {
        match symlink_metadata(path) {
            Err(e) if e.kind() == ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e.into()),
            Ok(meta) => Ok(Some(SystemTime::now().duration_since(meta.modified()?)?)),
        }
    }

    fn run(&mut self) -> Result<i32> {
        ensure!(!self.opt.paths.is_empty(), "No file/symlink to check");
        let mut res = vec![0];
        for p in &self.opt.paths {
            let age = self.age(p).with_context(|| string(p))?;
            self.ages.push(age);
            match (age, self.opt.critical, self.opt.warning) {
                (Some(a), Some(c), _) if a > *c => {
                    self.crit.push(string(p));
                    res.push(2)
                }
                (Some(a), _, Some(w)) if a > *w => {
                    self.warn.push(string(p));
                    res.push(1)
                }
                (None, _, _) if !self.opt.ignore_missing => {
                    self.miss.push(string(p));
                    res.push(2)
                }
                _ => (),
            }
        }
        Ok(res.into_iter().max().unwrap())
    }

    // format textual message
    fn deviations(&self) -> String {
        let mut res = vec![];
        let msg = |thres: Option<HDur>, paths: &[String]| {
            if thres.is_some() && !paths.is_empty() {
                Some(format!(
                    "older than {}: {}",
                    thres.unwrap(),
                    paths.join(", ")
                ))
            } else {
                None
            }
        };
        res.extend(msg(self.opt.critical, &self.crit));
        res.extend(msg(self.opt.warning, &self.warn));
        if !self.miss.is_empty() {
            res.push(format!("missing: {}", self.miss.join(", ")))
        }
        res.join(" - ")
    }

    // format perfdata
    fn performance<'a>(&'a self) -> impl Iterator<Item = String> + 'a {
        let warn: String = self
            .opt
            .warning
            .map(|w| w.as_secs().to_string())
            .unwrap_or_default();
        let crit: String = self
            .opt
            .critical
            .map(|w| w.as_secs().to_string())
            .unwrap_or_default();
        self.ages
            .iter()
            .zip(&self.opt.paths)
            .filter_map(move |(age, path)| {
                age.map(|a| format!(" {}={}s;{};{};0", path.display(), a.as_secs(), warn, crit))
            })
    }
}

impl fmt::Display for Check {
    fn fmt(&self, f: &mut fmt::Formatter) -> Result<(), fmt::Error> {
        match (self.crit.len() + self.miss.len(), self.warn.len()) {
            (0, 0) => write!(f, "OK: no outdated items")?,
            (0, _) => write!(f, "WARNING: {}", self.deviations())?,
            _ => write!(f, "CRITICAL: {}", self.deviations())?,
        }
        write!(f, " |{}", self.performance().collect::<Vec<_>>().join(""))
    }
}

/// Checks for outdated files and symlinks like stale `result` Nix store references. Note that this
/// check uses lstat() to determine the mtime of the symlink itself, not the target file.
#[derive(StructOpt, Debug)]
#[structopt(
    author,
    after_help = "DURATION accepts the following suffixes: s/m/h/d/w/y. \
                  Leaving -w/-c empty means no threshold.",
    max_term_width = 80
)]
struct Opt {
    /// Warning if at least one item is older than DURATION
    #[structopt(short, long, value_name = "DURATION")]
    warning: Option<HDur>,
    /// Critical if at least one item is older than DURATION
    #[structopt(short, long, value_name = "DURATION")]
    critical: Option<HDur>,
    /// Ignores missing files/symlinks silently
    #[structopt(short = "m", long)]
    ignore_missing: bool,
    /// file/symlink to check
    #[structopt(value_name = "PATH")]
    paths: Vec<PathBuf>,
}

fn main() {
    let opt = Opt::from_args();
    let mut c = Check::new(opt);
    match c.run() {
        Ok(exitcode) => {
            println!("CHECK_AGE {}", c);
            exit(exitcode);
        }
        Err(err) => {
            println!("CHECK_AGE UNKNOWN: {:#}", err);
            exit(3);
        }
    }
}
