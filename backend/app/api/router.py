"""API router including all route modules."""
from fastapi import APIRouter
from app.api.routes import health, db, auth, users, profile, ingredients, profile_health

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(db.router)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(profile.router)
api_router.include_router(ingredients.router)
api_router.include_router(profile_health.router)