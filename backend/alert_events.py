"""Compatibilidad con los imports de main.py; la implementación está en modules."""
from modules.alert_events import publish_alert_change

__all__ = ['publish_alert_change']
