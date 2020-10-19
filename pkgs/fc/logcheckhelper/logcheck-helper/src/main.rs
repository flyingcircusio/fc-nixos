use colored::Colorize;
use gumdrop::Options;
use regex::Regex;
use rustyline::Editor;
use std::collections::BTreeMap;
use std::error::Error;

/// Formats the regex as dict-of-lists YAML fragment.
fn format(re: &str) -> Result<String, Box<dyn Error>> {
    let mut ignore = BTreeMap::new();
    ignore.insert("ignore".to_owned(), vec![re.to_owned()]);
    Ok(serde_yaml::to_string(&ignore)?)
}

/// Queries the user as long as a matching pattern has been entered.
fn record_pattern(logmsg: &str) -> Result<String, Box<dyn Error>> {
    let mut rl = Editor::<()>::new();
    rl.add_history_entry(logmsg);
    loop {
        let pat = rl.readline(&format!("{} ", "ignore pattern>".purple().bold()))?;
        if pat.is_empty() {
            return Ok("".into());
        }
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
        rl.add_history_entry(pat);
    }
}

#[derive(Debug, Options)]
struct Opts {
    #[options(free)]
    log_message: Option<String>,
    help: bool,
}

fn run(opt: Opts) -> Result<String, Box<dyn Error>> {
    let mut rl = Editor::<()>::new();
    if let Some(logmsg) = opt.log_message {
        println!("{}> {}", "log message".cyan(), logmsg);
        record_pattern(&logmsg)
    } else {
        let logmsg = rl.readline(&format!("{} ", "log message>".cyan()))?;
        if !logmsg.is_empty() {
            record_pattern(&logmsg)
        } else {
            Err("no log message".into())
        }
    }
}

fn main() {
    match run(Opts::parse_args_default_or_exit()) {
        Ok(yaml) => println!("{}", yaml),
        Err(e) => {
            eprintln!("{}", e);
            std::process::exit(1)
        }
    }
}
