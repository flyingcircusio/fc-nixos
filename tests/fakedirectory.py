import json
from pathlib import Path
from xmlrpc.server import SimpleXMLRPCRequestHandler, SimpleXMLRPCServer


class RequestHandler(SimpleXMLRPCRequestHandler):
    rpc_paths = ()


class Directory(object):
    """A fake directory implementation to allow code in the integration
    tests to be properly exercised.
    """

    def evacuate_vms(self, node_name):
        return []

    def report_supported_cpu_models(self, specs):
        return ""

    def deletions(self, type_=""):
        return {}

    def list_virtual_machines(self, location):
        p = Path("/directory_response/list_virtual_machines").joinpath(location)
        if p.exists:
            return json.loads(p.read_text())
        return []

    def publish_backup_status(self, machine, status):
        return ""


# Create server
with SimpleXMLRPCServer(
    ("0.0.0.0", 80), requestHandler=RequestHandler
) as server:
    server.register_introspection_functions()
    server.register_instance(Directory())

    # Run the server's main loop
    server.serve_forever()
