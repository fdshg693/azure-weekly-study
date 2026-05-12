import azure.functions as func  # type: ignore
import logging
import random

app = func.FunctionApp()


@app.route(route="random", auth_level=func.AuthLevel.ANONYMOUS, methods=["GET"])
def random_number(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("random_number function processed a request.")

    try:
        lo = int(req.params.get("min", "1"))
        hi = int(req.params.get("max", "100"))
    except ValueError:
        return func.HttpResponse(
            "min/max must be integers",
            status_code=400,
            mimetype="text/plain",
        )

    if lo > hi:
        lo, hi = hi, lo

    value = random.randint(lo, hi)

    # HTMX が innerHTML としてそのまま差し込めるよう HTML 断片で返す
    return func.HttpResponse(
        f"<span>{value}</span>",
        status_code=200,
        mimetype="text/html",
    )
