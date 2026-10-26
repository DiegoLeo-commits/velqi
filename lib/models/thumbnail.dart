import 'package:get/get.dart';

class Thumbnail {
  Thumbnail(this._url);
  final String _url;
  String sizewith(int size) => (_url.contains("-rj"))
      ? "${_url.split("=")[0]}=w$size-h$size-l90-rj"
      : (_url.contains("=s"))
          ? "${_url.split("=s")[0]}=s$size"
          : (_url.contains("i.yti") && size >= 600)
              ? url.replaceFirst("sddefault", "maxresdefault")
              : url;
  String get url => _url;
  String get high => sizewith(720); //high-res cover art
  String get medium => sizewith(400);
  String get low => sizewith(200);
  String get extraHigh =>
      GetPlatform.isDesktop ? sizewith(1200) : sizewith(800);
}
