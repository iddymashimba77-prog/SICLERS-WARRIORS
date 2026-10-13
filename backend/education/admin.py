from django.contrib import admin

from .models import EducationCategory, EducationalContent


@admin.register(EducationCategory)
class EducationCategoryAdmin(admin.ModelAdmin):
    list_display = ("code", "name", "sort_order")
    ordering = ("sort_order", "name")


@admin.register(EducationalContent)
class EducationalContentAdmin(admin.ModelAdmin):
    list_display = (
        "uid", "title", "category", "status", "author", "published_at", "has_document",
    )
    list_filter = ("status", "category")
    readonly_fields = (
        "uid", "created_at", "updated_at", "document_name", "document_content_type",
        "document_size", "document_uploaded_at", "document_uploaded_by",
    )

    @admin.display(boolean=True, description="Handout")
    def has_document(self, obj):
        return bool(obj.document_file)