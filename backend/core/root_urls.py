from django.urls import path

from . import root_view

urlpatterns = [
    path("", root_view.root_index, name="root"),
]
