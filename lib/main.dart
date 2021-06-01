import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'dart:ffi';
import 'package:ffi/ffi.dart';

import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'package:flutter_spinkit/flutter_spinkit.dart';

final DynamicLibrary scrapeLib = DynamicLibrary.open('librrscrapelib.so');

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

final SpinKitPouringHourglass defaultLoader = SpinKitPouringHourglass(
	color: Colors.blue,
	size: 50,
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
	List<String> downloaded = new List<String>.filled(0, "", growable: true);

	Directory dir = await Directory(dirString).create(recursive: true);
	await for (var entity in dir.list(recursive: false, followLinks: false))
	{
		downloaded.add(entity.path.split("/").last);
	}

	downloaded.sort();

	return downloaded;
}

//Search Royal Road
final searchController = TextEditingController();

List<SearchResult> _scrapeSearch(String title)
{
	List<SearchResult> results = new List<SearchResult>.filled(0, new SearchResult("", ""), growable: true);
		
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
Future _scrape(ScrapeArg arg) async
{
	scrape(arg.url.toNativeUtf8(), arg.dir.toNativeUtf8());
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
	List<String> downloaded = new List<String>.filled(0, "", growable: true);

	@override
	void initState()
	{
		super.initState();
		asyncLoad();
	}

	void asyncLoad() async
	{
		Directory dir = await getApplicationDocumentsDirectory();
		String dirString = "${dir.path}/library";
		downloaded = await compute(_getDownloads, dirString);
		await compute(_updateDownloads, dirString);
		setState(() {_isLoading = false;});
	}

  	@override
  	Widget build(BuildContext context)
  	{
		return Scaffold(
			appBar: AppBar(
				title: Text(widget.title),
			),
			body: Center(
				child: Builder(
				builder: (BuildContext context)
					{
						if (_isLoading == true)
						{
							return SpinKitPouringHourglass(
								color: Colors.blue,
								size: 50,
							);
						}
						else
						{
							return ListView.separated(
								itemCount: downloaded.length,
								itemBuilder: (context, index)
								{
									return Container(
										child: ListTile(
											title: Text(downloaded[index]),
											onTap: ()
											{
												Navigator.push(
													context,
													MaterialPageRoute(builder: (context) => ChapterPage(title: downloaded[index]))
												);
											},
										),
									);
								},
								separatorBuilder: (context, index)
								{
									return Divider();
								},
							);
						}
					}
				)
			),
			floatingActionButton: FloatingActionButton(
				onPressed: ()
			  	{
					showDialog(
						context: context,
						builder: (BuildContext context) => _buildSearchDialog(context),
					);
				},
				tooltip: 'Search',
				child: Icon(Icons.search),
			),
		);
	}

	Widget _buildSearchDialog(BuildContext context)
	{
		return AlertDialog(
			content: Stack(
				clipBehavior: Clip.none,
				children: <Widget>[
					TextField(
						decoration: InputDecoration(
							border: OutlineInputBorder(),
							hintText: 'Search Royal Road'
						),
						controller: searchController,
					),
					
				]
			),
			actions: <Widget>[
			  	new TextButton(
					onPressed: () async
					{
					  	Navigator.of(context).pop();
						
						final _ = await Navigator.push(
							context,
							MaterialPageRoute(builder: (context) => ResultsPage())
						);
						searchController.clear();

						setState(() {_isLoading = true;});
						asyncLoad();
				  	},
				  	child: Text('Search')
			  	),
		  	]
	  	);
  	}
}

class ResultsPage extends StatefulWidget
{
	@override
	_ResultsPageState createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage>
{
	List<SearchResult> results = new List<SearchResult>.filled(0, new SearchResult("", ""), growable: true);
	bool _isLoading = true;

	@override
	void initState()
	{
		super.initState();
		asyncLoader();
	}

	void asyncLoader() async
	{
		results = await compute(_scrapeSearch, searchController.text);
		setState(() {_isLoading = false;});
	}

	@override
	Widget build(BuildContext context)
	{
		return Scaffold(
			appBar: AppBar(
				title: Text("Results")
			),
			body: Center(
				child: Builder(
					builder: (BuildContext context)
					{
						if (_isLoading == true)
						{
							return defaultLoader;
						}
						else
						{
							return ListView.separated(
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
							);
						}
					},
				)
			)
		);
	}
}

class ChapterPage extends StatefulWidget
{
	ChapterPage({Key? key, required this.title}) : super(key: key);

	final String title;

	@override
	_ChapterPageState createState() => _ChapterPageState();
}

class _ChapterPageState extends State<ChapterPage>
{
	bool _isLoading = true, _isLast = false, _isFirst = false;
	int chapter = 1;
	String chapterData = "";
	String dirString = "";

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
		File file = File("$dirString/$chapter.chapter");
		chapterData = await file.readAsString();

		if (chapter == 1)
		{
			_isFirst = true;
		}
		else
		{
			_isFirst = false;
		}
		if (!await File("$dirString/${chapter + 1}.chapter").exists())
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
			chapter++;
			asyncLoader();
		});
	}

	void back()
	{
		setState(()
		{
			_isLoading = true;
			chapter--;
			asyncLoader();
		});
	}

	@override
	Widget build(BuildContext context)
	{
		return Scaffold(
			appBar: AppBar(
				title: Text("Chapter $chapter")
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
							body: SingleChildScrollView(
								scrollDirection: Axis.vertical,
								child: Padding(
									child: Text(chapterData),
									padding: EdgeInsets.all(16),
								)
							),
						);
					}
				}
			) 
		);
	}
}