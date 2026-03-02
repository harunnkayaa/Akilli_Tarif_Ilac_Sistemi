"""API router including all route modules."""
from fastapi import APIRouter
from app.api.routes import health, db, auth, users, profile, ingredients, profile_health, recipes, drugs, intake, kitchen, llm

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(llm.router)
api_router.include_router(db.router)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(profile.router)
api_router.include_router(ingredients.router)
api_router.include_router(profile_health.router)
api_router.include_router(recipes.router)
api_router.include_router(drugs.router)
api_router.include_router(intake.router)
api_router.include_router(kitchen.router)
