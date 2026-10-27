import '../../core/emby/models/emby_item.dart';
import '../../data/catalog_api.dart';
import '../../data/tmdb_api.dart';

extension Artwork on CatalogApi {
  Uri? poster(EmbyItem item, {double width = 220}) {
    final w = (width * 1.5).round();
    final localized = item.localizedPosterPath;
    if (localized != null) return TmdbApi.imageUrl(localized, width: w);
    if (item.primaryImageTag != null && !item.isEpisode) {
      return image(item.id, ImageKind.primary, tag: item.primaryImageTag, width: w);
    }
    if (item.isEpisode && item.seriesId != null && item.seriesPrimaryImageTag != null) {
      return image(item.seriesId!, ImageKind.primary, tag: item.seriesPrimaryImageTag, width: w);
    }
    if (item.primaryImageTag != null) return image(item.id, ImageKind.primary, tag: item.primaryImageTag, width: w);
    return null;
  }

  Uri? landscape(EmbyItem item, {double width = 400, bool preferEpisodeStill = true}) {
    final w = (width * 1.5).round();
    if (item.isEpisode && preferEpisodeStill) {
      final still = item.localizedStillPath;
      if (still != null) return TmdbApi.imageUrl(still, width: w, backdrop: true);
      if (item.primaryImageTag != null) return image(item.id, ImageKind.primary, tag: item.primaryImageTag, width: w);
    }
    final localized = item.localizedBackdropPath;
    if (localized != null) return TmdbApi.imageUrl(localized, width: w, backdrop: true);
    if (item.thumbImageTag != null) return image(item.id, ImageKind.thumb, tag: item.thumbImageTag, width: w);
    if (item.backdropImageTags.isNotEmpty) {
      return image(item.id, ImageKind.backdrop, tag: item.backdropImageTags.first, width: w);
    }
    if (item.parentThumbItemId != null && item.parentThumbImageTag != null) {
      return image(item.parentThumbItemId!, ImageKind.thumb, tag: item.parentThumbImageTag, width: w);
    }
    if (item.parentBackdropItemId != null && item.parentBackdropImageTags.isNotEmpty) {
      return image(item.parentBackdropItemId!, ImageKind.backdrop, tag: item.parentBackdropImageTags.first, width: w);
    }
    if (item.primaryImageTag != null && (item.primaryImageAspectRatio ?? 0) > 1.2) {
      return image(item.id, ImageKind.primary, tag: item.primaryImageTag, width: w);
    }
    return null;
  }

  Uri? backdrop(EmbyItem item, {int width = 1920, int index = 0}) {
    final localized = item.localizedBackdropPath;
    if (localized != null && index == 0) return TmdbApi.imageUrl(localized, width: width, backdrop: true);
    if (item.backdropImageTags.isNotEmpty) {
      final i = index.clamp(0, item.backdropImageTags.length - 1);
      return image(item.id, ImageKind.backdrop, tag: item.backdropImageTags[i], width: width, index: i);
    }
    if (item.parentBackdropItemId != null && item.parentBackdropImageTags.isNotEmpty) {
      return image(item.parentBackdropItemId!, ImageKind.backdrop, tag: item.parentBackdropImageTags.first, width: width);
    }
    return null;
  }

  Uri? logo(EmbyItem item, {int width = 640}) {
    final localized = item.localizedLogoPath;
    if (localized != null) return TmdbApi.imageUrl(localized, width: width, logo: true);
    if (item.logoImageTag != null) return image(item.id, ImageKind.logo, tag: item.logoImageTag, width: width);
    if (item.parentLogoItemId != null && item.parentLogoImageTag != null) {
      return image(item.parentLogoItemId!, ImageKind.logo, tag: item.parentLogoImageTag, width: width);
    }
    return null;
  }

  Uri? personPhoto(Person p, {int width = 240}) {
    if (p.imageTag != null) return personImage(p, width: width);
    final localized = p.localizedImagePath;
    return localized == null ? null : TmdbApi.imageUrl(localized, width: width);
  }
}
