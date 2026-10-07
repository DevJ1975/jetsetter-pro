"""Money helpers. Amounts are Decimal end to end and strings on the wire."""
from decimal import ROUND_HALF_UP, Decimal

from django.conf import settings

# Currencies with no minor unit (Stripe's zero-decimal list).
ZERO_DECIMAL = {
    "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA",
    "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF",
}
# Three-decimal currencies. Stripe wants rounded amounts for these, so card
# checkout does not support them; offers still display fine.
THREE_DECIMAL = {"BHD", "JOD", "KWD", "OMR", "TND"}


def exponent(currency: str) -> int:
    code = currency.upper()
    if code in ZERO_DECIMAL:
        return 0
    if code in THREE_DECIMAL:
        return 3
    return 2


def quantize(amount: Decimal, currency: str) -> Decimal:
    return amount.quantize(Decimal(1).scaleb(-exponent(currency)), rounding=ROUND_HALF_UP)


def fmt(amount: Decimal | str | None, currency: str) -> str | None:
    if amount is None:
        return None
    return format(quantize(Decimal(str(amount)), currency), "f")


def to_minor_units(amount: Decimal, currency: str) -> int:
    return int(quantize(amount, currency).scaleb(exponent(currency)))


def card_checkout_supported(currency: str) -> bool:
    return currency.upper() not in THREE_DECIMAL


def service_fee(duffel_total: Decimal, currency: str) -> Decimal:
    """Markup on top of Duffel's total. Zero unless configured."""
    fee = duffel_total * settings.SERVICE_FEE_PERCENT / Decimal(100) + settings.SERVICE_FEE_FIXED
    return quantize(fee, currency) if fee > 0 else Decimal(0)
