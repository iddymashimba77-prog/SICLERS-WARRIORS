"""Content CMS routes (public home milestone). Mounted under ``/api/``.

    GET  /api/content/news/categories/                     public
    GET  /api/content/news/                                 public, published
    GET  /api/content/news/{uid}/                           public, published
    GET  /api/content/ticker/                               public, active
    GET  /api/admin/content/news/                           content.news.manage
    POST /api/admin/content/news/                           content.news.manage
    GET/PATCH/DELETE /api/admin/content/news/{uid}/         content.news.manage
    POST /api/admin/content/news/{uid}/publish|unpublish|archive|feature/
    POST /api/admin/content/news/{uid}/pin|unpin/            pinned to the top of the public list
    POST /api/admin/content/news/{uid}/restore/               undo a soft delete
    GET  /api/admin/content/news/?include_deleted=true       review deleted articles
    POST /api/admin/content/news/{uid}/cover/               multipart upload
    GET/POST /api/admin/content/ticker/                     content.ticker.manage
    GET/PATCH/DELETE /api/admin/content/ticker/{uid}/       content.ticker.manage
    POST /api/admin/content/ticker/{uid}/activate|deactivate/
"""

from django.urls import path
from rest_framework.routers import DefaultRouter

from content import views

router = DefaultRouter()
router.register("content/news", views.PublicNewsViewSet, basename="content-news")
router.register(
    "admin/content/news", views.AdminNewsViewSet, basename="content-admin-news",
)
router.register(
    "admin/content/ticker", views.AdminTickerViewSet, basename="content-admin-ticker",
)

urlpatterns = router.urls + [
    path(
        "content/news/categories/",
        views.PublicNewsCategoryListView.as_view(),
        name="content-news-categories",
    ),
    path(
        "content/ticker/",
        views.PublicTickerListView.as_view(),
        name="content-ticker",
    ),
]