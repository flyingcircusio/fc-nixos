#[cfg(test)]
mod test;

#[macro_use]
extern crate clap;

use clap::Arg;
use failure::{Error, Fallible};
use serde_derive::Deserialize;
use serde_json::Value;
use std::collections::HashMap;
use std::fmt;
use std::fs::File;
use std::io::BufReader;
use std::path::{Path, PathBuf};
use std::process;
use walkdir::Result as WResult;
use walkdir::WalkDir;

#[derive(Debug)]
enum Status {
    Good(usize), // `Ok` is already used by `Result`
    Warning(&'static str),
    Error(Error),
}

impl Status {
    fn code(&self) -> i32 {
        match self {
            Status::Good(_) => 0,
            Status::Warning(_) => 1,
            Status::Error(_) => 2,
        }
    }

    fn marker(&self) -> &'static str {
        match self {
            Status::Good(_) => "ok",
            Status::Warning(_) => "warn",
            Status::Error(_) => "crit",
        }
    }
}

impl fmt::Display for Status {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Status::Good(i) => write!(f, "{} check definition(s)", i),
            Status::Warning(msg) => write!(f, "{}", msg),
            Status::Error(e) => {
                let causes: Vec<_> = e.iter_chain().map(|c| c.to_string()).collect();
                write!(f, "{}", causes.join(": "))
            }
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct ClientDef {
    checks: HashMap<String, Value>,
}

impl ClientDef {
    fn decode<P: AsRef<Path>>(json: P) -> Fallible<Self> {
        Ok(serde_json::from_reader(BufReader::new(File::open(json)?))?)
    }
}

fn check(sensu_client_check: &Path) -> Status {
    let def = match ClientDef::decode(sensu_client_check) {
        Ok(def) => def,
        Err(e) => return Status::Error(e),
    };
    if def.checks.is_empty() {
        Status::Warning("does not contain any check definition")
    } else {
        Status::Good(def.checks.len())
    }
}

type CheckResults = Vec<(PathBuf, Status)>;

fn walk<P: AsRef<Path>>(sensu_config_dir: P) -> Fallible<CheckResults> {
    let entries = WalkDir::new(sensu_config_dir)
        .max_depth(1)
        .into_iter()
        .collect::<WResult<Vec<_>>>()?;
    Ok(entries
        .into_iter()
        .filter(|e| e.path().extension().unwrap_or_default() == "json" && !e.file_type().is_dir())
        .map(|e| {
            let stat = check(e.path());
            (e.into_path(), stat)
        })
        .collect())
}

fn output(mut res: CheckResults, show_statusline: bool) -> i32 {
    res.sort_by_key(|(_, s)| -s.code());
    let max = res.iter().map(|e| e.1.code()).max().unwrap_or_default();
    if show_statusline {
        let ncrit = res.iter().filter(|e| e.1.code() >= 2).count();
        let nwarn = res.iter().filter(|e| e.1.code() == 1).count();
        match max {
            0 => println!("OK: {} Sensu check config(s) found", res.len()),
            1 => println!("WARNING: {} warning(s)", nwarn),
            _ => println!("CRITICAL: {} error(s), {} warning(s)", ncrit, nwarn),
        }
    }
    res.iter()
        .for_each(|(p, s)| println!("[{}] {}: {}", s.marker(), p.display(), s));
    max
}

fn main() {
    let m = app_from_crate!()
        .arg(Arg::from_usage(
            "[NOSTATUS] -S --no-status 'Omit first line (status) from output'",
        ))
        .arg(
            Arg::from_usage("[DIR] -d --directory 'Searches for local sensu checks in DIR'")
                .default_value("/etc/local/sensu-client"),
        )
        .get_matches();
    match walk(m.value_of_os("DIR").unwrap()) {
        Ok(results) => process::exit(output(results, !m.is_present("NOSTATUS"))),
        Err(e) => {
            let causes: Vec<_> = e.iter_chain().map(|c| c.to_string()).collect();
            println!("UNKOWN: {}", causes.join(": "));
            process::exit(3)
        }
    }
}
