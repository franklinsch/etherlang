import Foundation
import Commander
import Diagnostic
import REPL


/// The main function for the compiler.
func main() {
    command (
        Argument<String> ("Contract path", description: "contract to be deployed"),
        Option<String>("address", default: "", description: "The address of an already deployed contract")
    )
    { contractFilePath, address in
        
        let repl = REPL(contractFilePath : contractFilePath, contractAddress : address)
        
        do {
            try repl.run()
        } catch let err {
            print(err)
        }

        }.run()
}

func main_d() throws {
    /*
    let fileName = "/Users/Zubair/Documents/Imperial/Thesis/Code/flint/ide_examples/curr_examples/test.flint"
    let inputFiles = [URL(fileURLWithPath: fileName)]
    let sourceCode = try String(contentsOf: inputFiles[0])
    do {
        
        let config = CompilerLSPConfiguration(sourceFiles: inputFiles,
                                              sourceCode: sourceCode,
                                              stdlibFiles: StandardLibrary.default.files,
                                              diagnostics: DiagnosticPool(shouldVerify: false,
                                                                          quiet: false,
                                                                          sourceContext: SourceContext(sourceFiles: inputFiles, sourceCodeString: sourceCode, isForServer: true)))
        let diags = try Compiler.ide_compile(config: config)
        let lsp_json = try convertFlintDiagToLspDiagJson(diags)
        print(lsp_json)
        
    } catch let err {
        let diagnostic = Diagnostic(severity: .error,
                                    sourceLocation: nil,
                                    message: err.localizedDescription)
        // swiftlint:disable force_try
        print(try! DiagnosticsFormatter(diagnostics: [diagnostic], sourceContext: nil).rendered())
        // swiftlint:enable force_try
        exit(1)
    }
   */
}

main()
