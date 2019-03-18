extern crate colored;
extern crate linefeed;
extern crate regex;
extern crate serde_yaml;

use colored::Colorize;
use linefeed::{Interface, ReadResult};
use regex::Regex;
use std::collections::BTreeMap;
use std::error::Error;

/// Formats the regex as dict-of-lists YAML fragment.
fn format(re: &str) -> Result<String, Box<Error>> {
    let mut ignore = BTreeMap::new();
    ignore.insert("ignore".to_owned(), vec![re.to_owned()]);
    Ok(serde_yaml::to_string(&ignore)?)
}

/// Queries the user as long as a matching pattern has been entered.
fn record_pattern(logmsg: &str) -> Result<String, Box<Error>> {
    let readline = Interface::new("")?;
    readline.add_history(logmsg.to_owned());
    readline.set_prompt(&format!("{}> ", "ignore pattern".purple()));
    loop {
        if let ReadResult::Input(pat) = readline.read_line()? {
            match Regex::new(&pat) {
                Err(e) => println!("{}\n{}", e, "invalid regex, try again".yellow()),
                Ok(re) => {
                    if re.is_match(&logmsg) {
                        println!("{}", "match".green());
                        return format(re.as_str());
                    } else {
                        println!("{}", "no match, try again".yellow());
                    }
                }
            }
            readline.add_history_unique(pat);
        } else {
            // empty pattern / eol / signalled
            return Ok(String::new());
        }
    }
}

fn run() -> Result<String, Box<Error>> {
    if let Some(logmsg) = std::env::args().nth(1) {
        println!("{}> {}", "log message".cyan(), logmsg);
        return record_pattern(&logmsg);
    }
    let readline = Interface::new("")?;
    readline.set_prompt(&format!("{}> ", "log message".cyan()));
    if let ReadResult::Input(logmsg) = readline.read_line()? {
        return record_pattern(&logmsg);
    }
    Err("no log message".into())
}

fn main() {
    match run() {
        Ok(yaml) => println!("{}", yaml),
        Err(e) => {
            eprintln!("{}", e.to_string().red());
            std::process::exit(1)
        }
    }
}
