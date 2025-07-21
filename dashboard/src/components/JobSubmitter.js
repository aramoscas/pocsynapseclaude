import React, { useState } from 'react';
import api from '../services/api';

export function JobSubmitter() {
  const [submitting, setSubmitting] = useState(false);
  const [lastJobId, setLastJobId] = useState(null);

  const submitTestJob = async () => {
    setSubmitting(true);
    try {
      const result = await api.submitJob({
        model_name: 'resnet50',
        input_data: { image: 'test.jpg', timestamp: Date.now() },
        priority: 1
      });
      setLastJobId(result.job_id);
      console.log('Job submitted:', result);
    } catch (error) {
      console.error('Failed to submit job:', error);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="p-4 bg-gray-800 rounded-lg">
      <h3 className="text-white mb-2">Test Job Submission</h3>
      <button
        onClick={submitTestJob}
        disabled={submitting}
        className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
      >
        {submitting ? 'Submitting...' : 'Submit Test Job'}
      </button>
      {lastJobId && (
        <p className="mt-2 text-sm text-gray-400">
          Last job ID: {lastJobId}
        </p>
      )}
    </div>
  );
}
