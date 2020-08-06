part of flutter_link_preview;

abstract class InfoBase {
  DateTime _timeout;
}

/// Web Information
class WebInfo extends InfoBase {
  final String title;
  final String icon;
  final String description;

  WebInfo({this.title, this.icon, this.description});
}

/// Image Information
class ImageInfo extends InfoBase {
  final String url;

  ImageInfo({this.url});
}

/// Video Information
class VideoInfo extends InfoBase {
  final String url;

  VideoInfo({this.url});
}

/// Web analyzer
class WebAnalyzer {
  static final Map<String, InfoBase> _map = {};
  static final RegExp _bodyReg = RegExp(r"<body[^>]*>([\s\S]*?)<\/body>");
  static final RegExp _scriptReg = RegExp(r"<script[^>]*>([\s\S]*?)<\/script>");
  static final RegExp _styleReg = RegExp(r"<style[^>]*>([\s\S]*?)<\/style>");
  static final RegExp _lineReg = RegExp(r"[\n\r]");
  static final RegExp _spaceReg = RegExp(r"\s+");

  /// Is it an empty string
  static bool isNotEmpty(String str) {
    return str != null && str.isNotEmpty;
  }

  /// Get web information
  /// return [InfoBase]
  static Future<InfoBase> getInfo(String url,
      {Duration cache, bool multimedia = true}) async {
    // final start = DateTime.now();
    InfoBase info = _map[url];
    if (info != null) {
      if (info._timeout.isAfter(DateTime.now())) {
        return info;
      } else {
        _map.remove(url);
      }
    }
    try {
      final response = await _requestUrl(url);

      if (response == null) return null;
      // print(response.request.headers);
      // print("$url ${response.statusCode}");
      if (multimedia) {
        final String contentType = response.headers["content-type"];
        if (contentType != null) {
          if (contentType.contains("image/")) {
            info = ImageInfo(url: url);
          } else if (contentType.contains("video/")) {
            info = VideoInfo(url: url);
          }
        }
      }

      info ??= await _getWebInfo(response, url, multimedia);

      if (cache != null && info != null) {
        info._timeout = DateTime.now().add(cache);
        _map[url] = info;
      }
    } catch (e) {
      print("Get web error:$url, Error:$e");
    }

    // print("$url cost ${DateTime.now().difference(start).inMilliseconds}");

    return info;
  }

  static final Map<String, String> _cookies = {
    "weibo.com":
        "YF-Page-G0=02467fca7cf40a590c28b8459d93fb95|1596707497|1596707497; SUB=_2AkMod12Af8NxqwJRmf8WxGjna49_ygnEieKeK6xbJRMxHRl-yT9kqlcftRB6A_dzb7xq29tqJiOUtDsy806R_ZoEGgwS; SUBP=0033WrSXqPxfM72-Ws9jqgMF55529P9D9W59fYdi4BXCzHNAH7GabuIJ"
  };

  static Future<Response> _requestUrl(String url,
      {int count = 0, String cookie}) async {
    Response res;
    final uri = Uri.parse(url);
    final client = Client();
    final request = Request('GET', uri)
      ..followRedirects = false
      ..headers["User-Agent"] =
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/84.0.4147.105 Safari/537.36"
      ..headers["cache-control"] = "no-cache"
      ..headers["Cookie"] = cookie ?? _cookies[uri.host]
      ..headers["accept"] = "*/*";
    // print(request.headers);
    final stream = await client.send(request);

    if (stream.statusCode == HttpStatus.movedTemporarily ||
        stream.statusCode == HttpStatus.movedPermanently) {
      if (stream.isRedirect && count < 6) {
        final String location = stream.headers['location'];
        if (location != null) {
          url = location;
          if (location.startsWith("/")) {
            url = uri.origin + location;
          }
        }
        if (stream.headers['set-cookie'] != null) {
          cookie = stream.headers['set-cookie'];
        }
        count++;
        client.close();
        // print("Redirect ====> $url");
        return _requestUrl(url, count: count, cookie: cookie);
      }
    } else if (stream.statusCode == HttpStatus.ok) {
      res = await Response.fromStream(stream);
    }
    client.close();
    if (res == null) print("Get web info empty($url)");
    return res;
  }

  static Future<InfoBase> _getWebInfo(
      Response response, String url, bool multimedia) async {
    if (response.statusCode == HttpStatus.ok) {
      String html;
      try {
        html = const Utf8Decoder().convert(response.bodyBytes);
      } catch (e) {
        try {
          html = gbk.decode(response.bodyBytes);
        } catch (e) {
          print("Web page resolution failure from:$url Error:$e");
        }
      }

      if (html == null) {
        print("Web page resolution failure from:$url");
        return null;
      }

      // Improved performance
      html = html.replaceFirst('<html">', "<html>");
      html = html.replaceAll(_scriptReg, "");
      html = html.replaceAll(_styleReg, "");
      final nobody = html.replaceFirst(_bodyReg, "<body></body>");
      final document = parser.parse(nobody);
      final uri = Uri.parse(url);

      // get image or video
      if (multimedia) {
        final gif = _analyzeGif(document, uri);
        if (gif != null) return gif;

        final video = _analyzeVideo(document, uri);
        if (video != null) return video;
      }

      final info = WebInfo(
        title: _analyzeTitle(document),
        icon: _analyzeIcon(document, uri),
        description: _analyzeDescription(document, html),
      );
      return info;
    }
    return null;
  }

  static InfoBase _analyzeGif(Document document, Uri uri) {
    if (_getMetaContent(document, "property", "og:image:type") == "image/gif") {
      final gif = _getMetaContent(document, "property", "og:image");
      if (gif != null) return ImageInfo(url: _handleUrl(uri, gif));
    }
    return null;
  }

  static InfoBase _analyzeVideo(Document document, Uri uri) {
    final video = _getMetaContent(document, "property", "og:video");
    if (video != null) return VideoInfo(url: _handleUrl(uri, video));
    return null;
  }

  static String _getMetaContent(
      Document document, String property, String propertyValue) {
    final meta = document.head.getElementsByTagName("meta");
    final ele = meta.firstWhere((e) => e.attributes[property] == propertyValue,
        orElse: () => null);
    if (ele != null) return ele.attributes["content"]?.trim();
    return null;
  }

  static String _analyzeTitle(Document document) {
    final title = _getMetaContent(document, "property", "og:title");
    if (title != null) return title;
    final list = document.head.getElementsByTagName("title");
    if (list.isNotEmpty) {
      final tagTitle = list.first.text;
      if (tagTitle != null) return tagTitle.trim();
    }
    return "";
  }

  static String _analyzeDescription(Document document, String html) {
    final desc = _getMetaContent(document, "property", "og:description");
    if (desc != null) return desc;

    final description = _getMetaContent(document, "name", "description") ??
        _getMetaContent(document, "name", "Description");

    if (!isNotEmpty(description)) {
      final allDom = parser.parse(html);
      String body = allDom.body.text ?? "";
      body = body.trim().replaceAll(_lineReg, " ").replaceAll(_spaceReg, " ");
      if (body.length > 200) {
        body = body.substring(0, 200);
      }
      return body;
    }
    return description;
  }

  static String _analyzeIcon(Document document, Uri uri) {
    final meta = document.head.getElementsByTagName("link");
    String icon = "";
    final metaIcon = meta.firstWhere((e) {
      final rel = (e.attributes["rel"] ?? "").toLowerCase();
      if (rel == "icon" || rel == "shortcut icon") {
        icon = e.attributes["href"];
        if (icon != null && !icon.toLowerCase().contains(".svg")) {
          return true;
        }
      }
      return false;
    }, orElse: () => null);

    if (metaIcon != null) {
      icon = metaIcon.attributes["href"];
    } else {
      return "${uri.origin}/favicon.ico";
    }

    return _handleUrl(uri, icon);
  }

  static String _handleUrl(Uri uri, String source) {
    if (isNotEmpty(source) && !source.startsWith("http")) {
      if (source.startsWith("//")) {
        source = "${uri.scheme}:$source";
      } else {
        if (source.startsWith("/")) {
          source = "${uri.origin}$source";
        } else {
          source = "${uri.origin}/$source";
        }
      }
    }
    return source;
  }
}
