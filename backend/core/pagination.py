"""Project-wide pagination (approved §03 API envelope).

All list endpoints share one page-numbered pagination class so clients get a
stable ``{count, next, previous, results}`` shape inside the global success
envelope::

    {"data": {"count": 42, "next": "...", "previous": null,
              "results": [...]}, "meta": {"correlation_id": "..."}}

Defaults (approved): page size 20, client may request ``?page_size=`` up to
100. A page size of zero is rejected by DRF defaults.
"""

from rest_framework.pagination import PageNumberPagination


class CorePageNumberPagination(PageNumberPagination):
    page_size = 20
    page_size_query_param = "page_size"
    max_page_size = 100