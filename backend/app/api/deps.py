from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from app.core.config import SECRET_KEY, ALGORITHM
from app.core.database import get_user_by_id

bearer = HTTPBearer(auto_error=False)

def get_current_user(creds: HTTPAuthorizationCredentials = Depends(bearer)):
    if creds is None or creds.scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="missing token")

    token = creds.credentials
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="invalid token")
    except JWTError:
        raise HTTPException(status_code=401, detail="invalid token")

    user = get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=401, detail="user not found")

    if not user["is_active"]:
        raise HTTPException(status_code=403, detail="user inactive")

    return user
