"""Reference-data list caching mixin (Stage 4.18 — NFR-PERF-001).

Used ONLY by read-only, PUBLIC or role-static reference lists (education
categories, symptom vocabulary). The mixin caches the serialized payload and
re-paginates it through the standard DRF paginator so the response envelope is
identical whether it hits the cache or the database.

Privacy guardrail (deny by default): do NOT attach this to any view whose
payload varies per user — cached lists must be identical for every caller.
"""

from rest_framework.response import Response

from core.cache import reference_get, reference_set


class ReferenceCachedListMixin:
    """Cache a static reference list.

    Attributes:
        reference_key: cache key (must be unique and non-user-scoped).
        reference_ttl: seconds the payload may be served from cache.
    """

    reference_key = None
    reference_ttl = 900

    def list(self, request, *args, **kwargs):
        assert self.reference_key, "ReferenceCachedListMixin needs reference_key"
        data = reference_get(self.reference_key)
        if data is None:
            data = self._load_reference()
            reference_set(self.reference_key, data, ttl=self.reference_ttl)
        return self._reference_response(data)

    def _load_reference(self):
        qs = self.get_queryset()
        return self.get_serializer(qs, many=True).data

    def _reference_response(self, data):
        if self.paginator is None:
            return Response(data)
        page = self.paginator.paginate_queryset(list(data), self.request, view=self)
        return self.paginator.get_paginated_response(page)