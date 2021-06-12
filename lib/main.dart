import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'dart:ffi';
import 'package:ffi/ffi.dart';

import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_spinkit/flutter_spinkit.dart';

final DynamicLibrary scrapeLib = Platform.isAndroid
	? DynamicLibrary.open('librrscrapelib.so')
	: DynamicLibrary.process();

typedef StringArr = Pointer<Pointer<Utf8>> Function(Pointer<Utf8>);

final StringArr scrapeSearch = scrapeLib
    .lookup<NativeFunction<StringArr>>("search")
    .asFunction();

typedef VoidFFI = void Function(Pointer<Utf8>, Pointer<Utf8>);
typedef void_ffi = Void Function(Pointer<Utf8>, Pointer<Utf8>);

final VoidFFI scrape = scrapeLib
	.lookup<NativeFunction<void_ffi>>("init_scrape")
	.asFunction();

typedef VoidUpdate = void Function(Pointer<Utf8>);
typedef void_update = Void Function(Pointer<Utf8>);

final VoidUpdate updateScrapes = scrapeLib
	.lookup<NativeFunction<void_update>>("update")
	.asFunction();

final Center defaultLoader = Center(
	child: SpinKitPouringHourglass(
		color: Colors.blue,
		size: 50,
	)
);

class SearchResult
{
	final String title;
	final String url;
	const SearchResult(this.title, this.url);
}

class ScrapeArg
{
	final String title;
	final String url;
	final String dir;
	const ScrapeArg(this.title, this.url, this.dir);
}

//Update downloads
void _updateDownloads(String dirString)
{
	updateScrapes(dirString.toNativeUtf8());
}

//Read Downloads
Future<List<String>> _getDownloads(String dirString) async
{
	List<String> downloaded = <String>[];

	Directory dir = await Directory(dirString).create(recursive: true);
	await for (var entity in dir.list(recursive: false, followLinks: false))
	{
		downloaded.add(entity.path.split("/").last);
	}

	downloaded.sort();

	return downloaded;
}

//Search Royal Road
List<SearchResult> _scrapeSearch(String title)
{
	List<SearchResult> results = <SearchResult>[];
		
   	Pointer<Pointer<Utf8>> arr = scrapeSearch(title.toNativeUtf8());

   	for (int x = 0; x < int.parse(arr.elementAt(0).value.toDartString()); x += 2)
   	{
   		results.add(new SearchResult(
			arr.elementAt(x + 1).value.toDartString(),
			arr.elementAt(x + 2).value.toDartString(),
		));
   	}
	
	return results;
}

//Scrape
void _scrape(ScrapeArg arg)
{
	scrape(arg.url.toNativeUtf8(), arg.dir.toNativeUtf8());
}

//Delete
void _deleteDir(String dirString) async
{
	await Directory(dirString).delete(recursive: true);
}

void main()
{
	runApp(MyApp());
}

class MyApp extends StatelessWidget
{
  	@override
  	Widget build(BuildContext context)
  	{
    	return MaterialApp(
      		title: 'RoyalRoadReader',
      		theme: ThemeData(
        		primarySwatch: Colors.blue,
      		),
      		home: MyHomePage(title: 'RoyalRoadReader Home')
    	);
  	}
}

class MyHomePage extends StatefulWidget
{
	MyHomePage({Key? key, required this.title}) : super(key: key);

	final String title;

	@override
	_MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
{
	bool _isLoading = true;
	List<String> downloaded = <String>[];

	@override
	void initState()
	{
		super.initState();
		asyncLoad();
	}

	void asyncLoad() async
	{
		List<Future<void>> futures = <Future>[];

		Directory dir = await getApplicationDocumentsDirectory();
		String dirString = "${dir.path}/library";
		downloaded = await compute(_getDownloads, dirString);

		await compute(_updateDownloads, "$dirString");

		setState(() {_isLoading = false;});
	}

  	@override
  	Widget build(BuildContext context)
  	{
		return Scaffold(
			appBar: AppBar(
				leading: Icon(Icons.home),
				title: Text("Home")
			),
			body: Builder(
				builder: (BuildContext context)
				{
					if (_isLoading == true)
					{
						return defaultLoader;
					}
					else
					{
						return Scrollbar(
							child: ListView.separated(
								itemCount: downloaded.length,
								itemBuilder: (context, index)
								{
									return Container(
										child: ListTile(
											title: Text(downloaded[index]),
											onTap: () async
											{
												Directory dir = await getApplicationDocumentsDirectory();
												File file = File("${dir.path}/library/${downloaded[index]}/.meta");
												String jsonString = await file.readAsString();
												Map<String, dynamic> data = jsonDecode(jsonString);

												Navigator.push(
													context,
													MaterialPageRoute(builder: (context) => ChapterPage(title: downloaded[index], jsonData: data,))
												);
											},
											onLongPress: () async
											{
												showDialog(
													barrierDismissible: false,
													context: context,
													builder: (BuildContext context) => _buildDeleteConfirm(context, downloaded[index])
												);
											},
										),
									);
								},
								separatorBuilder: (context, index)
								{
									return Divider();
								},
							)
						);
					}
				}
			),
			floatingActionButton: FloatingActionButton(
				onPressed: () async
				{
					final _ = await Navigator.push(
						context,
						MaterialPageRoute(builder: (context) => SearchPage())
					);

					setState(() {_isLoading = true;});
					asyncLoad();
			  	},
				tooltip: 'Search',
				child: Icon(Icons.search),
			),
		);
	}

	Widget _buildDeleteConfirm(BuildContext context, String storyName)
	{
		return AlertDialog(
			title: Row(
				children: <Widget>[
					Icon(Icons.delete),
					Text("Delete?"),
				],
			),
			content: Text("Are you sure you want to delete $storyName?"),
			actions: <Widget>[
				TextButton(
					child: Text("Cancel"),
					onPressed: ()
					{
						Navigator.pop(context);
					},
				),
				TextButton(
					child: Text("Confirm"),
					onPressed: () async
					{
						Navigator.pop(context);
						setState(() {_isLoading = true;});
						Directory dir = await getApplicationDocumentsDirectory();
						await compute(_deleteDir, "${dir.path}/library/$storyName");
						asyncLoad();
					},
				)
			],
		);
	}
}

class SearchPage extends StatefulWidget
{
	@override
	_SearchPage createState() => _SearchPage();
}

class _SearchPage extends State<SearchPage>
{
	List<SearchResult> results = <SearchResult>[];
	bool _isLoading = false;

	@override
	void initState()
	{
		super.initState();
	}

	@override
	Widget build(BuildContext context)
	{
		return Scaffold(
			appBar: AppBar(
				leading: IconButton(
					icon: Icon(Icons.arrow_back),
					onPressed: ()
					{
						Navigator.pop(context);
					},
				),
				title: TextField(
					decoration: InputDecoration(
						focusedBorder: UnderlineInputBorder(
							borderSide: BorderSide(color: Colors.grey.shade800)
						),
						hintText: "Search Royal Road",
					),
					cursorColor: Colors.grey.shade800,
					onSubmitted: (String searchTerm) async
					{
						setState(() {_isLoading = true;});
						results = await compute(_scrapeSearch, searchTerm);
						setState(() {_isLoading = false;});
					},
				)
			),
			body: Builder(
				builder: (BuildContext context)
				{
					if (_isLoading == true)
					{
						return defaultLoader;
					}
					else
					{
						return Scrollbar(
							child: ListView.separated(
								itemCount: results.length,
								itemBuilder: (itemContext, index)
								{
									return Container(
										child: ListTile(
											title: Text(results[index].title),
											onTap: () async
											{
												setState(()
												{
													_isLoading = true;
												});
												Directory dir = await getApplicationDocumentsDirectory();
												String dirString = "${dir.path}/library/${results[index].title}";
												ScrapeArg arg = ScrapeArg(results[index].title, results[index].url, dirString);
												await compute(_scrape, arg);
												Navigator.pop(context);
											},
										),
									);
								},
								separatorBuilder: (context, index)
								{
									return Divider();
								},
							)
						);
					}
				},
			),
		);
	}
}

class ChapterPage extends StatefulWidget
{
	ChapterPage({Key? key, required this.title, required this.jsonData}) : super(key: key);

	final String title;
	Map<String, dynamic> jsonData;

	@override
	_ChapterPageState createState() => _ChapterPageState();
}

class _ChapterPageState extends State<ChapterPage>
{
	List<int> chapterList = <int>[];
	bool _isLoading = true, _isLast = false, _isFirst = false;
	int maxChapters = -1;
	String chapterData = "", dirString = "";

	@override
	void initState()
	{
		super.initState();
		asyncLoader();
	}

	void asyncLoader() async
	{
		Directory dir = await getApplicationDocumentsDirectory();
		dirString = "${dir.path}/library/${widget.title}";
		File file = File("$dirString/${widget.jsonData["last_read"]}.chapter");
		chapterData = await file.readAsString();

		file = File("$dirString/.meta");
		await file.writeAsString(jsonEncode(widget.jsonData));

		if (maxChapters == -1)
		{
			List<String> maxChaptersList = await compute(_getDownloads, dirString);
			maxChapters = maxChaptersList.length;
			for (int i = 1; i < maxChapters; i++)
			{
				chapterList.add(i);
			}
		}

		if (widget.jsonData["last_read"] == 1)
		{
			_isFirst = true;
		}
		else
		{
			_isFirst = false;
		}
		if (widget.jsonData["last_read"] + 1 == maxChapters)
		{
			_isLast = true;
		}
		else
		{
			_isLast = false;
		}

		setState(() {_isLoading = false;});
	}

	void forward()
	{
		setState(()
		{
			_isLoading = true;
			widget.jsonData["last_read"]++;
			asyncLoader();
		});
	}

	void back()
	{
		setState(()
		{
			_isLoading = true;
			widget.jsonData["last_read"]--;
			asyncLoader();
		});
	}

	@override
	Widget build(BuildContext context)
	{
		return Scaffold(
			appBar: AppBar(
				title: Text("Chapter ${widget.jsonData["last_read"]}")
			),
			body: Builder(
				builder: (BuildContext context)
				{
					if (_isLoading == true)
					{
						return Center(
							child: defaultLoader,
						);
					}
					else
					{
						return Scaffold(
							bottomNavigationBar: BottomAppBar(
								child: Row(
									children: <Widget>[
										TextButton(
											onPressed: _isFirst ? null : back,
											style: TextButton.styleFrom(
												primary: _isFirst ? Colors.grey : Colors.teal,
											),
											child: Row(
												children: <Widget>[
													Icon(Icons.arrow_back),
													Text("Back"),
												],
											)
										),
										Spacer(),
										DropdownButton(
											value: widget.jsonData["last_read"] as int,
											items: chapterList.map((num)
											{
												return DropdownMenuItem<int>(
													value: num,
													child: Text("Chapter $num")
												);
											}).toList(),
											onChanged: (int? value)
											{
												setState(()
												{
													_isLoading = true;
													widget.jsonData["last_read"] = value as int;
													asyncLoader();
												});
											},
										),
										Spacer(),
										TextButton(
											onPressed: _isLast ? null : forward,
											style: TextButton.styleFrom(
												primary: _isLast ? Colors.grey : Colors.teal,
											),
											child: Row(
												children: <Widget>[
													Text("Next"),
													Icon(Icons.arrow_forward),
												],
											)
										),
									],
								),
							),
							body: Scrollbar(
								child: SingleChildScrollView(
									scrollDirection: Axis.vertical,
									child: Padding(
										child: Text(chapterData),
										padding: EdgeInsets.all(16),
									)
								),
							)
						);
					}
				}
			) 
		);
	}
}