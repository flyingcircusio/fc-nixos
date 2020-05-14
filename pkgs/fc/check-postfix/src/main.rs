use anyhow::{bail, ensure, Context, Result};
use regex::Regex;
use std::path::PathBuf;
use std::process::exit;
use structopt::StructOpt;
use subprocess::{Exec, Redirection::Pipe};

#[derive(Debug, PartialEq)]
enum State {
    OK = 0,
    WARNING,
    CRITICAL,
}

fn check_num_reqs(out: &str, warn: u32, crit: u32) -> Result<State> {
    if let Some(cap) = Regex::new(r"in (\d+) Request").expect("RE").captures(&out) {
        let n = cap[1].parse::<u32>().context("number of requests")?;
        let state = match n {
            _ if n > crit => State::CRITICAL,
            _ if n > warn => State::WARNING,
            _ => State::OK,
        };
        println!("POSTFIX MAILQ {:?}: {} mail(s) waiting", state, n);
        Ok(state)
    } else if out.find("Mail queue is empty").is_some() {
        println!("POSTFIX MAILQ OK: No mails waiting");
        Ok(State::OK)
    } else {
        bail!("Format not recognized")
    }
}

fn run(opt: &Opt) -> Result<State> {
    let c = Exec::cmd(&opt.mailq)
        .stdout(Pipe)
        .env("LANG", "C")
        .capture()
        .with_context(|| format!("Failed to execute {:?}", opt.mailq))?;
    ensure!(c.success(), "{:?} status: {:?}", &opt.mailq, c.exit_status);
    let out = c.stdout_str();
    let state = check_num_reqs(&out, opt.warn, opt.crit).context("Failed to parse mailq output")?;
    if opt.verbose {
        print!("{}", out);
    }
    Ok(state)
}

#[derive(StructOpt, Debug, Default)]
struct Opt {
    /// Warning if there are more than N mails in the queue
    #[structopt(short, long, default_value = "25", value_name = "N", display_order = 1)]
    warn: u32,
    /// Critical if there are more than N mails in the queue
    #[structopt(short, long, default_value = "50", value_name = "N", display_order = 2)]
    crit: u32,
    /// Prints full `mailq` output
    #[structopt(short, long)]
    verbose: bool,
    /// Path to the `mailq` binary
    #[structopt(long, default_value = "mailq", value_name = "PATH", parse(from_os_str))]
    mailq: PathBuf,
}

fn main() {
    let opt = Opt::from_args();
    match run(&opt) {
        Ok(state) => {
            exit(state as i32);
        }
        Err(error) => {
            println!("POSTFIX MAILQ UNKNOWN: {:#}", error);
            exit(3)
        }
    }
}

#[cfg(test)]
mod test {
    use super::*;

    static OUT0: &str = "\
Mail queue is empty
";
    static OUT1: &str = "\
----Queue ID----- --Size-- ---Arrival Time---- --Sender/Recipient------
49Mdqs22btz3wWJZ       485 Wed May 13 17:28:57 root@mail.test.fcio.net
  (connect to nun[2a01:4f8:191:1234::2]:8025: Connection refused)
                                               user@test.fcio.net

-- 0 Kbytes in 1 Request.
";
    static OUT2: &str = "\
----Queue ID----- --Size-- ---Arrival Time---- --Sender/Recipient------
49Mdkt2nWWz3wWJY       485 Wed May 13 17:24:38 root@mail.test.fcio.net
  (connect to nun[2a01:4f8:191:1234::2]:8025: Connection refused)
                                               user@test.fcio.net

49Mdqs22btz3wWJZ       485 Wed May 13 17:28:57 root@mail.test.fcio.net
  (connect to nun[2a01:4f8:191:1234::2]:8025: Connection refused)
                                               user@test.fcio.net

-- 0 Kbytes in 2 Requests.
";

    #[test]
    fn test_parse() {
        assert_eq!(check_num_reqs(OUT0, 0, 1).unwrap(), State::OK);
        assert_eq!(check_num_reqs(OUT1, 0, 1).unwrap(), State::WARNING);
        assert_eq!(check_num_reqs(OUT1, 0, 0).unwrap(), State::CRITICAL);
        assert_eq!(check_num_reqs(OUT2, 0, 1).unwrap(), State::CRITICAL);
    }

    #[test]
    fn test_parse_garbage() {
        assert!(check_num_reqs("", 0, 0).is_err());
        assert!(check_num_reqs("hello world", 0, 0).is_err());
    }
}
