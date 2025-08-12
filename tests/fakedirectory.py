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

    def list_resource_groups(self):
        return []

    def store_s3_traffic(self, measured_values):
        # We cannot really test this since the sync only
        # reads in past hours, not the current hour. This is to make
        # sure that we don't account people twice.
        # However, this also means that we'd have to wait 60min
        # to check for S3 data (and apparently moving around dates of
        # log objects isn't really a thing in radosgw).
        return []

# Create server
with SimpleXMLRPCServer(
    ("0.0.0.0", 80), requestHandler=RequestHandler
) as server:
    server.register_introspection_functions()
    server.register_instance(Directory())

    # Run the server's main loop
    server.serve_forever()
