"""Pydantic v2 request/response schemas. Plain snake_case JSON everywhere."""

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

# --- shared bits ---


class ReportType(StrEnum):
    obstacle = "obstacle"
    disease = "disease"
    water = "water"


class EmergencyContact(BaseModel):
    name: str | None = None
    phone: str | None = None


class PlaintextMedical(BaseModel):
    """Medical card fields broadcast openly in an SOS (see master plan §5)."""

    name: str | None = None
    blood_group: str | None = None
    allergies: list[str] | None = None
    emergency_contact: EmergencyContact | None = None


class SosStatus(StrEnum):
    active = "active"
    responding = "responding"
    resolved = "resolved"


class ConfirmResult(BaseModel):
    id: uuid.UUID
    confirm_count: int
    last_confirmed_at: datetime


# --- SOS ---


class SosCreate(BaseModel):
    device_id: str | None = None  # client-generated UUID string; non-UUID -> stored NULL
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    plaintext_medical: PlaintextMedical | None = None
    encrypted_medical: str | None = None  # opaque base64 AES-GCM ciphertext
    client_msg_id: str | None = None  # Phase 3 mesh message id for idempotent relay flush


class SosEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    device_id: uuid.UUID | None
    lat: float
    lng: float
    plaintext_medical: dict[str, Any] | None
    encrypted_medical: str | None
    client_msg_id: uuid.UUID | None
    status: str
    created_at: datetime


class SosCreated(BaseModel):
    id: uuid.UUID
    status: Literal["active"] = "active"
    created_at: datetime


# --- Reports ---


class ReportCreate(BaseModel):
    type: ReportType
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    description: str | None = None
    device_id: str | None = None
    client_msg_id: str | None = None  # Phase 3 mesh message id for idempotent relay flush


class ReportOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    type: str
    lat: float
    lng: float
    description: str | None
    device_id: uuid.UUID | None
    client_msg_id: uuid.UUID | None
    confirm_count: int
    last_confirmed_at: datetime | None
    created_at: datetime


class ClusterOut(BaseModel):
    cluster_id: str
    centroid_lat: float
    centroid_lng: float
    report_count: int
    total_confirmations: int
    last_confirmed_at: datetime | None
    sample_description: str | None
    report_ids: list[uuid.UUID]


class ClusterResultOut(BaseModel):
    clusters: list[ClusterOut]
    noise: list[uuid.UUID]


# --- Missing persons ---


class MissingPersonCreate(BaseModel):
    name: str = Field(min_length=1)
    last_seen_lat: float | None = Field(default=None, ge=-90, le=90)
    last_seen_lng: float | None = Field(default=None, ge=-180, le=180)
    description: str | None = None
    reporter_device_id: str | None = None


class MissingPersonOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    last_seen_lat: float | None
    last_seen_lng: float | None
    description: str | None
    reporter_device_id: uuid.UUID | None
    status: str
    created_at: datetime


# --- Shelters ---


class ShelterCreate(BaseModel):
    name: str = Field(min_length=1)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    contact_info: str | None = None
    added_by: str | None = None


class ShelterOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    lat: float
    lng: float
    contact_info: str | None
    confirm_count: int
    last_confirmed_at: datetime | None
    added_by: uuid.UUID | None
