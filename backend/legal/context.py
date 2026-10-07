from django.conf import settings


def site(_request):
    return {
        "app_name": settings.APP_NAME,
        "company_name": settings.COMPANY_NAME,
        "support_email": settings.SUPPORT_EMAIL,
    }
