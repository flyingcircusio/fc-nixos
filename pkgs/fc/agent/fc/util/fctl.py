import fc.maintenance.cli
import fc.util.postgresql
import typer

app = typer.Typer()
app.add_typer(fc.maintenance.cli.app, name="maintenance")
app.add_typer(fc.util.postgresql.app, name="postgresql")
