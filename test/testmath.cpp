// Copyright 2010-2013 UT-Battelle, LLC.  See LICENSE.txt for more information.
#include "eavl.h"
#include "eavlCUDA.h"
#include "eavlFilter.h"
#include "eavlDataSet.h"
#include "eavlTimer.h"
#include "eavlException.h"

#include "eavlImporterFactory.h"
#include "eavlVTKExporter.h"

#include "eavlBinaryMathMutator.h"
#include "eavlUnaryMathMutator.h"
#include "eavlExecutor.h"


eavlDataSet *ReadWholeFile(const string &filename)
{
    eavlImporter *importer = eavlImporterFactory::GetImporterForFile(filename);
    
    if (!importer)
        THROW(eavlException,"Didn't determine proper file reader to use");

    string mesh = importer->GetMeshList()[0];
    eavlDataSet *out = importer->GetMesh(mesh, 0);
    vector<string> allvars = importer->GetFieldList(mesh);
    for (size_t i=0; i<allvars.size(); i++)
        out->AddField(importer->GetField(allvars[i], mesh, 0));

    return out;
}
 
void WriteToVTKFile(eavlDataSet *data, const string &filename,
        int cellSetIndex = 0)
{
    ofstream out(filename.c_str());

    eavlVTKExporter exporter(data, cellSetIndex);
    exporter.Export(out);
    out.close();

}

int main(int argc, char *argv[])
{
    try
    {   
        eavlExecutor::SetExecutionMode(eavlExecutor::PreferGPU);
        eavlInitializeGPU();

        if (argc != 4 && argc != 5)
            THROW(eavlException,"Incorrect number of arguments");

        // Read the input
        eavlDataSet *data = ReadWholeFile(argv[1]);

        eavlBinaryMathMutator *math = new eavlBinaryMathMutator();
        math->SetDataSet(data);
        math->SetField1(argv[2]);
        math->SetField2(argv[3]);

        math->SetOperation(eavlBinaryMathMutator::Add);
        math->SetResultName(string(argv[2]) + "_plus_" + argv[3]);
        math->Execute();

        math->SetOperation(eavlBinaryMathMutator::Subtract);
        math->SetResultName(string(argv[2]) + "_minus_" + argv[3]);
        math->Execute();

        math->SetOperation(eavlBinaryMathMutator::Multiply);
        math->SetResultName(string(argv[2]) + "_times_" + argv[3]);
        math->Execute();

        eavlUnaryMathMutator *umath = new eavlUnaryMathMutator();
        umath->SetDataSet(data);
        umath->SetOperation(eavlUnaryMathMutator::Negate);

        umath->SetField(argv[2]);
        umath->SetResultName(string("neg_") + argv[2]);
        umath->Execute();

        umath->SetField(argv[3]);
        umath->SetResultName(string("neg_") + argv[3]);
        umath->Execute();

        if (argc == 5)
        {
            cerr << "\n\n-- done with operations, writing to file --\n";	
            WriteToVTKFile(data, argv[4]);
        }
        else
        {
            cerr << "No output filename given; not writing result\n";
        }


        cout << "\n\n-- summary of data set result --\n";	
        data->PrintSummary(cout);
    }
    catch (const eavlException &e)
    {
        cerr << e.GetErrorText() << endl;
        cerr << "\nUsage: "<<argv[0]<<" <infile.vtk> <field1name> <field2name> [<outfile.vtk>]\n";
        return 1;
    }


    return 0;
}
