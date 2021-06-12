use std::os::raw::{c_char};
use std::ffi::{CString, CStr};

use select::document::Document;
use select::predicate::{Class, Name, Predicate};

use std::fs::File;
use std::fs;
use std::io::prelude::*;
use std::path::PathBuf;

use serde_json::json;
use serde::{Deserialize, Serialize};

use std::thread;

#[derive(Serialize, Deserialize)]
struct MetaData
{
	url: String,
	chap_num: usize,
	last_read: i32,
}

#[no_mangle]
pub extern fn enforce_binding()
{
	println!("binding enforced");
}

#[no_mangle]
pub extern fn search(title: *const c_char) -> *const *mut c_char 
{
	let title = match unsafe { CStr::from_ptr(title) }.to_str()
	{
		Err(_) => "ERROR",
		Ok(string) => string,
	};

	let url = format!("https://www.royalroad.com/fictions/search?title={}", title);

	let resp = reqwest::blocking::get(&url)
		.unwrap()
		.text()
		.unwrap();

	let document = Document::from(resp.as_str());

	let mut results: Vec<CString> = Vec::new();

	for node in document.find(Class("fiction-title").descendant(Name("a")))
	{
		results.push(CString::new(node
			.text()
			.clone())
			.unwrap());

		results.push(CString::new(String::from(node
			.attr("href")
			.unwrap()))
			.unwrap());
	}

	results.insert(0, CString::new(format!("{}", results.len()))
		.unwrap());

	let results = results
		.into_iter()
		.map(|s| s.into_raw())
		.collect::<Vec<_>>();

	results.as_ptr()
}

#[no_mangle]
pub extern fn init_scrape(url: *const c_char, dir_str: *const c_char)
{
	let url = match unsafe { CStr::from_ptr(url) }.to_str()
	{
		Err(_) => "ERROR",
		Ok(string) => string,
	};

	let dir_str = match unsafe { CStr::from_ptr(dir_str) }.to_str()
	{
		Err(_) => "ERROR",
		Ok(string) => string,
	};

	let mut url: String = format!("https://www.royalroad.com{}", url);

	let client = reqwest::blocking::Client::new();
	let resp = client.get(&url)
		.send()
		.unwrap()
		.text()
		.unwrap();
	
	let document = Document::from(resp.as_str());

	for node in document.find(Class("fic-buttons").descendant(Name("a"))).take(1)
	{
		url = format!("https://www.royalroad.com{}", node.attr("href").unwrap());
	}

	let tuple = scrape_internal(url);
	let chapters = tuple.0;
	let link = tuple.1;

	let mut path = PathBuf::from(dir_str);
	let mut i = 1;
	let filename = path.file_name().unwrap().to_str().unwrap().to_owned();

	loop
	{
		if path.exists()
		{
			path.pop();
			path.push(format!("{}({})", &filename, i));
			i += 1;
		}
		else
		{
			fs::create_dir_all(&path).unwrap();
			break;
		}
	}

	
	for i in 0..chapters.len()
	{
		path.push(format!("{}.chapter", i + 1));
		let mut file = File::create(&path).unwrap();
		file.write_all(chapters[i].as_bytes()).unwrap();
		path.pop();
	}

	path.push(".meta");
	let mut file = File::create(&path).unwrap();

	file.write_all(json!(MetaData
	{
		url: link,
		chap_num: chapters.len(),
		last_read: 1,
	}).to_string().as_bytes()).unwrap();
}

#[no_mangle]
pub extern fn update(dir: *const c_char)
{
	let dir = match unsafe { CStr::from_ptr(dir) }.to_str()
	{
		Err(_) => "ERROR",
		Ok(string) => string,
	};

	let stories = fs::read_dir(&dir).unwrap();
	let mut handles: Vec<std::thread::JoinHandle<()>> = Vec::new();

	for p in stories
	{
		let p = p.unwrap();
		handles.push(thread::spawn(move ||
		{
			update_story(&mut p.path());
		}));
	}

	for handle in handles
	{
		handle.join().unwrap();
	}
}

fn update_story(path: &mut PathBuf)
{
	path.push(".meta");
	let mut input = File::open(&path).unwrap();
	let mut data_str = String::new();
	input.read_to_string(&mut data_str).unwrap();
	
	let mut data: MetaData = serde_json::from_str(&data_str).unwrap();

	path.pop();

	let client = reqwest::blocking::Client::new();
	let resp = client.get(&data.url)
		.send()
		.unwrap()
		.text()
		.unwrap();
		
	let document = Document::from(resp.as_str());
		
	for node in document.find(Class("chapter-page").descendant(Class("nav-buttons")).descendant(Class("col-lg-offset-6")).descendant(Class("col-xs-12"))).take(1)
	{
		match node.attr("disabled")
		{
			None => data.url = format!("https://www.royalroad.com{}", node.attr("href").unwrap()),
			Some(_) => data.url = String::new(),
		};
	}

	if !data.url.is_empty()
	{
		let tuple = scrape_internal(data.url);
		let chapters = tuple.0;
		let link = tuple.1;

		for i in 0..chapters.len()
		{
			path.push(format!("{}.chapter", i + data.chap_num + 1));
			let mut file = File::create(&path).unwrap();
			file.write_all(chapters[i].as_bytes()).unwrap();
			path.pop();
		}

		data.url = link;
		data.chap_num += chapters.len() - 1;
	
		path.push(".meta");
		let mut file = File::create(&path).unwrap();
		file.write_all(json!(data).to_string().as_bytes()).unwrap();
	}
}

fn scrape_internal(url: String) -> (Vec<String>, String)
{
	let mut url = url;
	let mut links = true;
	let mut chapters: Vec<String> = Vec::new();
	let client = reqwest::blocking::Client::new();

	while links
	{
		let resp = client.get(&url)
			.send()
			.unwrap()
			.text()
			.unwrap();
	
		let document = Document::from(resp.as_str());
	
		for node in document.find(Class("chapter-content")).take(1)
		{
			chapters.push(str::replace(&node.text().trim(), "\n", "\n\n"));
		}
	
		for node in document.find(Class("chapter-page").descendant(Class("nav-buttons")).descendant(Class("col-lg-offset-6")).descendant(Class("col-xs-12"))).take(1)
		{
			match node.attr("disabled")
			{
				None => url = format!("https://www.royalroad.com{}", node.attr("href").unwrap()),
				Some(_) => links = false,
			};
		}
	}

	(chapters, url)
}